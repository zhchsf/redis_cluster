require "spec_helper"

describe "slot calculater" do
  context "when has { and } in the key" do
    it "would be equal with key 'test' and '{test}xxxx' " do
      r1 = RedisCluster::Slot.slot_by("test")
      r2 = RedisCluster::Slot.slot_by("{test}xxxx")
      expect(r1).to eq r2
    end

    it "would not equal with key '{test}xxx' and '{tes}t}xxx' " do
      r1 = RedisCluster::Slot.slot_by("{test}xxx")
      r2 = RedisCluster::Slot.slot_by("{tes}t}xxx")
      expect(r1).to_not eq r2
    end

    it "would use all for key when blank between {}" do
      r1 = RedisCluster::Slot.slot_by("{}xxx")
      r2 = RedisCluster::Slot.slot_by("")
      expect(r1).to_not eq r2
    end
  end
end