require 'thread'

module RedisCluster

  class Client

    def initialize(hosts, configs = {})
      @hosts = hosts.dup
      @initial_hosts = hosts.dup

      # Extract configuration options relevant to Redis Cluster.

      # force_cluster defaults to true to match the client's behavior before
      # the option existed
      @force_cluster = configs.delete(:force_cluster) { |_key| true }

      # An optional logger. Should respond like the standard Ruby `Logger`:
      #
      # http://ruby-doc.org/stdlib-2.4.0/libdoc/logger/rdoc/Logger.html
      @logger = configs.delete(:logger) { |_key| nil }

      # The number of times to retry a failed execute. Redis errors, `MOVE`, or
      # `ASK` are all considered failures that will count towards this tally. A
      # count of at least 2 is probably sensible because if a node disappears
      # the first try will be a Redis error, the second try retry will probably
      # be a `MOVE` (whereupon the node pool is reloaded), and it will take
      # until the third try to succeed.
      @retry_count = configs.delete(:retry_count) { |_key| 3 }

      # Any leftover configuration goes through to the pool and onto individual
      # Redis clients.
      @pool = Pool.new(configs)
      @mutex = Mutex.new

      reload_pool_nodes(true)
    end

    def execute(method, args, &block)
      asking = false
      last_error = nil
      retries_left = @retry_count
      try_random_node = false

      # We use `>= 0` instead of `> 0` because we decrement this counter on the
      # first run.
      while retries_left >= 0
        retries_left -= 1

        begin
          return @pool.execute(method, args, {asking: asking, random_node: try_random_node}, &block)

        rescue Errno::ECONNREFUSED, Redis::TimeoutError, Redis::CannotConnectError, Errno::EACCES => e
          last_error = e

          # Getting an error while executing may be an indication that we've
          # lost the node that we were talking to and in that case it makes
          # sense to try a different node and maybe reload our node pool (if
          # the new node issues a `MOVE`).
          try_random_node = true

          unless @logger.nil?
            @logger.error("redis_cluster: Received error: #{e} retries_left=#{retries_left}")
          end

        rescue => e
          last_error = e

          err_code = e.to_s.split.first

          unless %w(MOVED ASK).include?(err_code)
            unless @logger.nil?
              @logger.error("redis_cluster: Received error: #{e} retries_left=#{retries_left}")
            end

            raise e
          end

          unless @logger.nil?
            @logger.debug("redis_cluster: Received ASK/MOVED: #{e} retries_left=#{retries_left}")
          end

          if err_code == 'ASK'
            asking = true
          else
            # `MOVED` indicates a permanent redirect which means that our slot
            # mappings are stale: reload them.
            reload_pool_nodes(false)
          end
        end
      end

      # If we ran out of retries (the maximum number may have been set to 0),
      # surface any error that was thrown back to the caller. We'd otherwise
      # suppress the error, which would return something quite unexpected.
      raise last_error
    end

    Configuration.method_names.each do |method_name|
      define_method method_name do |*args, &block|
        execute(method_name, args, &block)
      end
    end

    def method_missing(method, *args, &block)
      execute(method, args, &block)
    end

    # Closes all open connections and reloads the client pool.
    #
    # Normally host information from the last time the node pool was reloaded
    # is used, but if the `use_initial_hosts` is set to `true`, then the client
    # is completely refreshed and the hosts that were specified when creating
    # it originally are set instead.
    def reconnect(options = {})
      use_initial_hosts = options.fetch(:use_initial_hosts, false)

      @hosts = @initial_hosts.dup if use_initial_hosts

      @mutex.synchronize do
        @pool.nodes.each{|node| node.connection.close}
        @pool.nodes.clear
        reload_pool_nodes_unsync(true)
      end
    end

    private

    # Adds only a single node to the client pool and sets it result for the
    # entire space of slots. This is useful when running either a standalone
    # Redis or a single-node Redis Cluster.
    def create_single_node_pool
      host = @hosts
      if host.is_a?(Array)
        if host.length > 1
          raise ArgumentError, "Can only create single node pool for single host"
        end

        # Flatten the configured host so that we can easily add it to the
        # client pool.
        host = host.first
      end

      @pool.add_node!(host, [(0..Configuration::HASH_SLOTS)])

      unless @logger.nil?
        @logger.info("redis_cluster: Initialized single node pool: #{host}")
      end
    end

    def create_multi_node_pool(raise_error)
      unless @hosts.is_a?(Array)
        raise ArgumentError, "Can only create multi-node pool for multiple hosts"
      end

      @hosts.each do |options|
        begin
          redis = Node.redis(@pool.global_configs.merge(options))
          slots_mapping = redis.cluster("slots").group_by{|x| x[2]}
          @pool.delete_except!(slots_mapping.keys)
          slots_mapping.each do |host, infos|
            slots_ranges = infos.map {|x| x[0]..x[1] }
            @pool.add_node!({host: host[0], port: host[1]}, slots_ranges)
          end
        rescue Redis::CommandError => e
          if e.message =~ /cluster\ support\ disabled$/
            if !@force_cluster
              # We're running outside of cluster-mode -- just create a
              # single-node pool and move on. The exception is if we've been
              # asked for force Redis Cluster, in which case we assume this is
              # a configuration problem and maybe raise an error.
              create_single_node_pool
              return
            elsif raise_error
              raise e
            end
          end

          unless @logger.nil?
            @logger.error("redis_cluster: Received error: #{e}")
          end

          raise e if e.message =~ /NOAUTH\ Authentication\ required/

          next
        rescue => e
          unless @logger.nil?
            @logger.error("redis_cluster: Received error: #{e}")
          end

          next
        end

        # We only need to see a `CLUSTER SLOTS` result from a single host, so
        # break after one success.
        break
      end

      unless @logger.nil?
        mappings = @pool.nodes.map{|node| "#{node.slots} -> #{node.options}"}
        @logger.info("redis_cluster: Initialized multi-node pool: #{mappings}")
      end
    end

    # Reloads the client node pool by requesting new information with `CLUSTER
    # SLOTS` or just adding a node directly if running on standalone. Clients
    # are "upserted" so that we don't necessarily drop clients that are still
    # relevant.
    def reload_pool_nodes(raise_error)
      @mutex.synchronize do
        reload_pool_nodes_unsync(raise_error)
      end
    end

    # The same as `#reload_pool_nodes`, but doesn't attempt to synchronize on
    # the mutex. Use this only if you've already got a lock on it.
    def reload_pool_nodes_unsync(raise_error)
      if @hosts.is_a?(Array)
        create_multi_node_pool(raise_error)
        refresh_startup_nodes
      else
        create_single_node_pool
      end
    end

    # Refreshes the contents of @hosts based on the hosts currently in
    # the client pool. This is useful because we may have been told about new
    # hosts after running `CLUSTER SLOTS`.
    def refresh_startup_nodes
      @pool.nodes.each {|node| @hosts.push(node.host_hash) }
      @hosts.uniq!
    end

  end # end client

end
