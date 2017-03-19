module RedisCluster

  class Configuration
    HASH_SLOTS = 16384
    REQUEST_TTL = 16
    DEFAULT_TIMEOUT = 1

    SUPPORT_SINGLE_NODE_METHODS = %w(persist expire expireat ttl pexpire pexpireat pttl dump restore del exists move type decr decrby incr incrby
        incrbyfloat set setex psetex setnx get setrange getrange setbit getbit append bitcount bitpos getset strlen [] []= llen lpush lpushx rpush
        rpushx lpop rpop blpop brpop lindex linsert lrange lrem lset ltrim scard sadd srem spop srandmember sismember smembers zcard zadd zincrby 
        zrem zscore zrange zrevrange zrank zrevrank zremrangebyrank zrangebyscore zrevrangebyscore zremrangebyscore zcount hlen hset hsetnx 
        hmset mapped_hmset hget hmget mapped_hmget hdel hexists hincrby hincrbyfloat hkeys hvals hgetall publish pfadd
      )

    SUPPORT_MULTI_NODE_METHODS = %w(keys multi pipelined)
  end

end
