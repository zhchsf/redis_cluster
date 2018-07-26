module RedisCluster

  class Pool
    attr_reader :nodes, :global_configs

    def initialize(global_configs = {})
      @nodes = []
      @global_configs = global_configs
    end

    # TODO: type check
    def add_node!(node_options, slots)
      new_node = Node.new(global_configs.merge(node_options))
      node = @nodes.find { |n| n.name == new_node.name } || new_node
      node.slots = slots
      @nodes.push(node).uniq!
    end

    def delete_except!(master_hosts)
      names = master_hosts.map { |host, port| "#{host}:#{port}" }
      @nodes.delete_if { |n| !names.include?(n.name) }
    end

    # other_options:
    #   asking
    #   random_node
    def execute(method, args, other_options, &block)
      return send(method, args, &block) if Configuration::SUPPORT_MULTI_NODE_METHODS.include?(method.to_s)

      key = key_by_command(method, args)
      raise CommandNotSupportedError.new(method.upcase) if key.nil?

      node = other_options[:random_node] ? random_node : node_by(key)
      node.asking if other_options[:asking]
      node.execute(method, args, &block)
    end

    def keys(args, &block)
      glob = args.first
      on_each_node(:keys, glob).flatten
    end

    def script(args, &block)
      on_each_node(:script, *args).flatten
    end

    # Now mutli & pipelined conmand must control keys at same slot yourself
    # You can use hash tag: '{foo}1'
    def multi(args, &block)
      random_node.execute :multi, args, &block
    end

    def pipelined(args, &block)
      random_node.execute :pipelined, args, &block
    end

    # Implements scan across all nodes in the pool.
    # Cursors will behave strangely if the node list changes during iteration.
    def scan(args)
      scan_cursor = args.first
      options = args[1] || {}
      node_cursor, node_index = decode_scan_cursor(scan_cursor)
      next_node_cursor, result = @nodes[node_index].execute("scan", [node_cursor, options])
      [encode_next_scan_cursor(next_node_cursor, node_index), result]
    end

    private

    def encode_next_scan_cursor(next_node_cursor, node_index)
      if next_node_cursor == '0'
        # '0' indicates the end of iteration.  Advance the node index and
        # start at the '0' position on the next node.  If this was the last node,
        # loop around and return '0' to indicate iteration is done.
        ((node_index + 1) % @nodes.size)
      else
        ((next_node_cursor.to_i * @nodes.size) + node_index)
      end.to_s # Cursors are strings
    end

    def decode_scan_cursor(cursor)
      node_cursor, node_index = cursor.to_i.divmod(@nodes.size)
      [node_cursor.to_s, node_index] # Cursors are strings.
    end

    def node_by(key)
      slot = Slot.slot_by(key)
      @nodes.find { |node| node.has_slot?(slot) }
    end

    def random_node
      @nodes.sample
    end

    def key_by_command(method, args)
      case method.to_s.downcase
      when 'info', 'exec', 'slaveof', 'config', 'shutdown'
        nil
      when 'eval', 'evalsha'
        if args[1].nil? || args[1].empty?
          raise KeysNotSpecifiedError.new(method.upcase)
        end

        unless Slot.at_one?(args[1])
          raise KeysNotAtSameSlotError.new(args[1])
        end

        return args[1][0]
      else
        return args.first
      end
    end

    def on_each_node(method, *args)
      @nodes.map do |node|
        node.execute(method, args)
      end
    end

  end # end pool

end
