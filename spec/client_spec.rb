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

  # context "failover" do
  #   let(:nodes) {@redis.instance_variable_get("@pool").nodes}
  #   before :each do
  #     key_slot_map = {a: 15495, b: 3300, c: 7365, d: 11298, e: 15363, f: 3168}
  #   end

  #   it "redetect nodes" do
  #     cluster_nodes = [
  #       [1000, 5460, ["127.0.0.1", 7003], ["127.0.0.1", 7000]], 
  #       [0, 999, ["127.0.0.1", 7006], ["127.0.0.1", 7007]], 
  #       [15001, 16383, ["127.0.0.1", 7006], ["127.0.0.1", 7007]], 
  #       [10923, 15000, ["127.0.0.1", 7002], ["127.0.0.1", 7005]], 
  #       [5461, 10922, ["127.0.0.1", 7004], ["127.0.0.1", 7001]]
  #     ]
  #     allow_any_instance_of(Redis).to receive(:cluster).and_return(cluster_nodes)

  #     expect_any_instance_of(Redis).to receive(:get).once.and_raise("MOVED 15495 127.0.0.1:7006")
  #     expect_any_instance_of(Redis).to receive(:get).and_return("ok wang")

  #     puts @redis.get("a")
  #     puts nodes.map{|n| n.slots}
  #   end
  # end
end
