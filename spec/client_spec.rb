require "spec_helper"

describe "client" do
  before do
    cluster_nodes = [
      [1000, 5460, ["127.0.0.1", 7003], ["127.0.0.1", 7000]], 
      [0, 999, ["127.0.0.1", 7006], ["127.0.0.1", 7007]], 
      [10923, 16383, ["127.0.0.1", 7002], ["127.0.0.1", 7005]], 
      [5461, 10922, ["127.0.0.1", 7004], ["127.0.0.1", 7001]]
    ]
    allow_any_instance_of(Redis).to receive(:cluster).and_return(cluster_nodes)

    hosts = [{host: '127.0.0.1', port: '7000'}]
    @redis = RedisCluster::Client.new(hosts)
  end

  context "nodes auto detect" do
    let(:nodes) {@redis.instance_variable_get("@pool").nodes}

    it "will get host 127.0.0.1 in pool" do
      hosts = nodes.map{|n| n.host_hash[:host] }
      expect(hosts).to include "127.0.0.1"
    end

    it "will get master port 7003 7006 7002 7004" do
      ports = nodes.map{|n| n.host_hash[:port] }
      [7003, 7006, 7002, 7004].each do |port|
        expect(ports).to include port
      end
    end
  end

  context "failover" do
    before :each do
      key_slot_map = {a: 15495, b: 3300, c: 7365, d: 11298, e: 15363, f: 3168}
      @value = "ok wang"

      cluster_nodes = [
        [1000, 5460, ["127.0.0.1", 7003], ["127.0.0.1", 7000]],
        [0, 999, ["127.0.0.1", 7006], ["127.0.0.1", 7007]],
        [15001, 16383, ["127.0.0.1", 7006], ["127.0.0.1", 7007]],
        [10923, 15000, ["127.0.0.1", 7002], ["127.0.0.1", 7005]],
        [5461, 10922, ["127.0.0.1", 7004], ["127.0.0.1", 7001]]
      ]
      allow_any_instance_of(Redis).to receive(:cluster).and_return(cluster_nodes)

      redis_7002 = double("7002")
      allow(redis_7002).to receive(:get).and_raise("MOVED 15495 127.0.0.1:7006")
      @redis.instance_variable_get("@pool").nodes.find {|node| node.instance_variable_get("@options")[:port] == 7002 }.instance_variable_set("@connection", redis_7002)

      redis_7006 = double("7006")
      allow(redis_7006).to receive(:get).and_return(@value)
      @redis.instance_variable_get("@pool").nodes.find {|node| node.instance_variable_get("@options")[:port] == 7006 }.instance_variable_set("@connection", redis_7006)
    end

    it "redetect nodes and get right redis value" do
      expect(@redis.get("a")).to eq @value

      node_7006 = @redis.instance_variable_get("@pool").nodes.find {|node| node.instance_variable_get("@options")[:port] == 7006 }
      expect(node_7006.has_slot? 15495).to be_truthy
    end
  end

  describe "multi nodes command" do
    context "keys with 'test*'" do
      before :each do
        [[7002, []], [7003, ['test111', 'test222']], [7004, []], [7006, ['test333']]].each do |port , values|
          redis_obj = double(port)
          allow(redis_obj).to receive(:keys).and_return(values)
          @redis.instance_variable_get("@pool").nodes.find {|node| node.instance_variable_get("@options")[:port] == port }.instance_variable_set("@connection", redis_obj)
        end
        @keys = @redis.keys "test*"
      end

      it "has 3 keys" do
        expect(@keys.length).to eq 3
      end

      it "include all node keys" do
        ['test111', 'test222', 'test333'].each do |key|
          expect(@keys).to include key
        end
      end
    end
  end
end
