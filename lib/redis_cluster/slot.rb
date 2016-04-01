module RedisCluster

  class Slot
    KEY_PATTERN = /\{([^\}]*)\}/

    # key "{xxx}ooo" will calculate "xxx" for slot
    # if key is "{}dddd", calculate "{}dddd" for slot
    def self.slot_by(key)
      KEY_PATTERN =~ key
      key = $1 if $1 && !$1.empty?
      CRC16.crc16(key) % Configuration::HASH_SLOTS
    end

  end # end Slot

end
