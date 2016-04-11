module RedisCluster

  class Pool
    attr_reader :nodes

    def initialize
      @nodes = []
    end

    # TODO: type check
    def add_node!(node_options, slots)
      new_node = Node.new(node_options)
      node = @nodes.find {|n| n.name == new_node.name } || new_node
      node.slots = slots
      @nodes.push(node).uniq!
    end

    def delete_except!(master_hosts)
      names = master_hosts.map {|host, port| "#{host}:#{port}" }
      @nodes.delete_if {|n| !names.include?(n.name) }
    end

    # other_options:
    #   asking
    #   random_node
    def execute(method, args, other_options)
      key = key_by_command(method, args)
      raise "not usable" if key.nil?

      node = other_options[:random_node] ? random_node : node_by(key)
      node.asking if other_options[:asking]
      node.execute(method, args)
    end

    private

    def node_by(key)
      slot = Slot.slot_by(key)
      @nodes.find {|node| node.has_slot?(slot) }
    end

    def random_node
      @nodes.sample
    end

    def key_by_command(method, args)
      case method.to_s.downcase
      when 'info', 'multi', 'exec', 'slaveof', 'config', 'shutdown'
        nil
      else
        return args.first
      end
    end

  end # end pool

end
