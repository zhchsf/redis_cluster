require "spec_helper"

describe "node" do
  subject { RedisCluster::Node.new(host: '127.0.0.1', port: 6379) }

  context "basic infos" do

    it "have a name" do
      expect(subject.name).to eq "127.0.0.1:6379"
    end

  end

  context "slots" do
    let(:slots_arr) {
      [1..100, 200..300]
    }

    before :each do
      subject.slots = slots_arr
    end

    it "has slot 10 and 290" do
      expect(subject.has_slot?(10)).to be_true
      expect(subject.has_slot?(290)).to be_true
    end

    it "has not slot 110" do
      expect(subject.has_slot?(110)).to_not be_true
    end
  end

  context "redis connection" do
    it "has a redis connection" do
      expect(subject.connection.class.name).to eq "Redis"
    end
  end
end
