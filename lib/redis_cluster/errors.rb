module RedisCluster
  NotSupportError = Class.new StandardError

  KeysNotAtSameSlotError = Class.new StandardError

  KeyNotAppointError = Class.new StandardError
end
