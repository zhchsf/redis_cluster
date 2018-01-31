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

      # The number of times to retry when it detects a failure that looks like
      # it might be intermittent.
      #
      # It might be worth setting this to `0` if you'd like full visibility
      # around what kinds of errors are occurring. Possibly in conjunction with
      # your own out-of-library retry loop and/or circuit breaker.
      @retry_count = configs.delete(:retry_count) { |_key| 2 }

      # Any leftover configuration goes through to the pool and onto individual
      # Redis clients.
      @pool = Pool.new(configs)
      @mutex = Mutex.new

      reload_pool_nodes
    end

    def execute(method, args, &block)
      asking = false
      retried = false

      # Note that there are two levels of retry loops here.
      #
      # The first is for intermittent failures like "host unreachable" or
      # timeouts. These are retried a number of times equal to @retry_count.
      #
      # The second is when it receives an `ASK` or `MOVED` error response from
      # Redis. In this case the client will complete re-enter its execution
      # loop and retry the command after any necessary prework (if `MOVED`, it
      # will attempt to reload the node pool first). This will only ever be
      # retried one time (see notes below). This loop uses Ruby's `retry`
      # syntax for blocks, so keep an eye out for that in the code below.
      #
      # It's worth noting that if these conditions ever combine, you could see
      # more network attempts than @retry_count. An initial execution attempt
      # might fail intermittently a couple times before sending a `MOVED`. The
      # client will then attempt to reload the node pool, an operation which is
      # also retried for intermittent failures. It could then return to the
      # main execution and fail another couple of times intermittently. This
      # should be an extreme edge case, but it's worth considering if you're
      # running at large scale.
      begin
        retry_intermittent_loop do |attempt|
          # Getting an error while executing may be an indication that we've
          # lost the node that we were talking to and in that case it makes
          # sense to try a different node and maybe reload our node pool (if
          # the new node issues a `MOVE`).
          try_random_node = attempt > 0

          return @pool.execute(method, args, {asking: asking, random_node: try_random_node}, &block)
        end
      rescue Redis::CommandError => e
        unless @logger.nil?
          @logger.error("redis_cluster: Received error: #{e}")
        end

        # This is a special condition to protect against a misbehaving library
        # or server. After we've gotten one ASK or MOVED and retried once,
        # we'll never do so a second time. Receiving two of any operations in a
        # row is probably indicative of a problem and we don't want to get
        # stuck in an infinite retry loop.
        raise if retried
        retried = true

        err_code = e.to_s.split.first
        case err_code
        when 'ASK'
          unless @logger.nil?
            @logger.info("redis_cluster: Received ASK; retrying operation (#{e})")
          end

          asking = true
          retry

        when 'MOVED'
          unless @logger.nil?
            @logger.info("redis_cluster: Received MOVED; retrying operation (#{e})")
          end

          # `MOVED` indicates a permanent redirect which means that our slot
          # mappings are stale: reload them then try what we were doing again
          reload_pool_nodes
          retry

        else
          raise
        end
      end
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
        reload_pool_nodes_unsync
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

    def create_multi_node_pool
      unless @hosts.is_a?(Array)
        raise ArgumentError, "Can only create multi-node pool for multiple hosts"
      end

      begin
        retry_intermittent_loop do |attempt|
          # Try a random host from our seed pool.
          options = @hosts.sample

          redis = Node.redis(@pool.global_configs.merge(options))
          slots_mapping = redis.cluster("slots").group_by{|x| x[2]}
          @pool.delete_except!(slots_mapping.keys)
          slots_mapping.each do |host, infos|
            slots_ranges = infos.map {|x| x[0]..x[1] }
            @pool.add_node!({host: host[0], port: host[1]}, slots_ranges)
          end
        end
      rescue Redis::CommandError => e
        unless @logger.nil?
          @logger.error("redis_cluster: Received error: #{e}")
        end

        if e.message =~ /cluster\ support\ disabled$/ && !@force_cluster
          # We're running outside of cluster-mode -- just create a single-node
          # pool and move on. The exception is if we've been asked for force
          # Redis Cluster, in which case we assume this is a configuration
          # problem and maybe raise an error.
          create_single_node_pool
          return
        end

        raise
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
    def reload_pool_nodes
      @mutex.synchronize do
        reload_pool_nodes_unsync
      end
    end

    # The same as `#reload_pool_nodes`, but doesn't attempt to synchronize on
    # the mutex. Use this only if you've already got a lock on it.
    def reload_pool_nodes_unsync
      if @hosts.is_a?(Array)
        create_multi_node_pool
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

    # Retries an operation @retry_count times for intermittent connection
    # errors. After exhausting retries, the error that was received on the last
    # attempt is raised to the user.
    def retry_intermittent_loop
      last_error = nil

      for attempt in 0..(@retry_count) do
        begin
          yield(attempt)

          # Fall through on any success.
          return
        rescue Errno::EACCES, Redis::TimeoutError, Redis::CannotConnectError => e
          last_error = e

          unless @logger.nil?
            @logger.error("redis_cluster: Received error: #{e} retries_left=#{@retry_count - attempt}")
          end
        end
      end

      # If we ran out of retries (the maximum number may have been set to 0),
      # surface any error that was thrown back to the caller. We'd otherwise
      # suppress the error, which would return something quite unexpected.
      raise last_error
    end

  end # end client

end
