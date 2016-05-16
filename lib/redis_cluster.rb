require "redis_cluster/version"
require "redis"

module RedisCluster
  
  class << self

    # startup_hosts examples:
    #   [{host: 'xxx', port: 'xxx'}, {host: 'xxx', port: 'xxx'}, ...]
    # global_configs:
    #   now not used, options for later versions
    def new(startup_hosts, *global_configs)
      @client = Client.new(startup_hosts, global_configs)
    end

  end

end

require "redis_cluster/configuration"
require "redis_cluster/client"
require "redis_cluster/node"
require "redis_cluster/pool"
require "redis_cluster/slot"
require "redis_cluster/crc16"
require "redis_cluster/errors"
