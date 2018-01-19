module RedisCluster
  class CommandNotSupportedError < StandardError
    def initialize(command)
      super("Command #{command} is not supported for Redis Cluster")
    end
  end

  class KeysNotAtSameSlotError < StandardError
    def initialize(keys)
      super("Keys must map to the same Redis Cluster slot when using " \
        "EVAL/EVALSHA. Consider using Redis Cluster 'hash tags' (see " \
        "documentation). Keys: #{keys}")
    end
  end

  class KeysNotSpecifiedError < StandardError
    def initialize(command)
      super("Keys must be specified for command #{command}")
    end
  end

  # These error classes were renamed. These aliases are here for backwards
  # compatibility.
  KeyNotAppointError = KeysNotSpecifiedError
  NotSupportError = CommandNotSupportedError
end
