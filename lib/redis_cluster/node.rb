module RedisCluster

  class Node
    attr_accessor :options

    # slots is a range array: [1..100, 300..500]
    attr_accessor :slots

    #
    # basic requires:
    #   {host: xxx.xxx.xx.xx, port: xxx}
    # redis cluster don't support select db, use default 0
    #
    def initialize(opts)
      @options = opts
      @slots = []
    end

    def name
      "#{@options[:host]}:#{@options[:port]}"
    end

    def host_hash
      {host: @options[:host], port: @options[:port]}
    end

    def has_slot?(slot)
      slots.any? {|range| range.include? slot }
    end

    def asking
      execute(:asking)
    end

    def execute(method, args, &block)
      connection.public_send(method, *args, &block)
    end

    def connection
      @connection ||= self.class.redis(options)
    end

    def host_uri(options)
      "redis://#{options[:host]}:#{options[:port]}/0"
    end

    def self.redis(options)
      ::EM::Hiredis.connect(host_uri(options))
    end

  end # end Node

end
