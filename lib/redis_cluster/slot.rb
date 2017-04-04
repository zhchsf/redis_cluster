module RedisCluster

  class Slot
    KEY_PATTERN = /\{([^\}]*)\}/

    # hash tag key "{xxx}ooo" will calculate "xxx" for slot
    # if key is "{}dddd", calculate "{}dddd" for slot
    def self.slot_by(key)
      key = key.to_s
      KEY_PATTERN =~ key
      key = $1 if $1 && !$1.empty?
      CRC16.crc16(key) % Configuration::HASH_SLOTS
    end

    # check if keys at same slot
    def self.at_one?(keys)
      keys.map { |k| slot_by(k) }.uniq.size == 1
    end

  end # end Slot

end
