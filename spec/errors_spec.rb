require "spec_helper"

# These tests are extremely trivial (purposely so because it gives us a little
# more flexibility around changing error messages), but are here to demonstrate
# that these exceptions can be initialized without error and also shows their
# basic usage.
describe "errors" do
  describe RedisCluster::CommandNotSupportedError do
    it "initializes" do
      RedisCluster::CommandNotSupportedError.new("GET")
    end
  end

  describe RedisCluster::KeysNotAtSameSlotError do
    it "initializes" do
      RedisCluster::KeysNotAtSameSlotError.new(["foo", "bar"])
    end
  end

  describe RedisCluster::KeysNotSpecifiedError do
    it "initializes" do
      RedisCluster::KeysNotSpecifiedError.new("GET")
    end
  end
end
