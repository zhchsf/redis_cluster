require "spec_helper"

describe "node" do
  subject { RedisCluster::Node.new(host: '127.0.0.1', port: 6379) }

  shared_examples "slots include" do |slot|
    it "has slot #{slot}" do
      expect(subject.has_slot? slot).to be_truthy
    end
  end

  shared_examples "slots exclude" do |slot|
    it "has not slot #{slot}" do
      expect(subject.has_slot? slot).to_not be_truthy
    end
  end

  context "basic infos" do

    it "have a name" do
      expect(subject.name).to eq "127.0.0.1:6379"
    end

  end

  context "slots" do
    before :each do
      subject.slots = [1..100, 200..300]
    end

    it_behaves_like "slots include", 10

    it_behaves_like "slots include", 290

    it_behaves_like "slots exclude", 110
  end

  context "redis connection" do
    it "has a redis connection" do
      expect(subject.connection.class.name).to eq "Redis"
    end
  end
end
