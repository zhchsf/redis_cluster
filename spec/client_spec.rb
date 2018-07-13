require "spec_helper"

describe "client" do
  let(:pool)       {@redis.instance_variable_get("@pool")}
  let(:pool_nodes) {pool.nodes}
  let(:pool_hosts) {pool_nodes.map{|n| n.host_hash[:host]}}
  let(:pool_ports) {pool_nodes.map{|n| n.host_hash[:port]}}

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

  context "standalone Redis" do
    it "initializes single node pool" do
      # Note that unlike many examples, this `host` is a Hash instead of an
      # array which directly indicates to the gem that we want a standalone
      # Redis.
      host = {host: '127.0.0.1', port: '7000'}

      @redis = RedisCluster::Client.new(host)
      expect(pool_hosts).to eq(["127.0.0.1"])
      expect(pool_ports).to eq(["7000"])
    end
  end

  context "nodes auto detect" do
    it "will get host 127.0.0.1 in pool" do
      expect(pool_hosts).to include "127.0.0.1"
    end

    it "will get master port 7003 7006 7002 7004" do
      [7003, 7006, 7002, 7004].each do |port|
        expect(pool_ports).to include port
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
      allow(redis_7002).to receive(:get).and_raise(Redis::CommandError.new("MOVED 15495 127.0.0.1:7006"))
      @redis.instance_variable_get("@pool").nodes.find {|node| node.instance_variable_get("@options")[:port] == 7002 }.instance_variable_set("@connection", redis_7002)

      redis_7006 = double("7006")
      allow(redis_7006).to receive(:get).and_return(@value)
      @redis.instance_variable_get("@pool").nodes.find {|node| node.instance_variable_get("@options")[:port] == 7006 }.instance_variable_set("@connection", redis_7006)
    end

    it "redetect nodes and get right redis value" do
      expect(@redis.get("a")).to eq @value

      node_7006 = pool_nodes.find {|node| node.instance_variable_get("@options")[:port] == 7006 }
      expect(node_7006.has_slot? 15495).to be_truthy
    end
  end

  describe "multi nodes command" do
    context "keys with 'test*'" do
      before :each do
        [[7002, []], [7003, ['test111', 'test222']], [7004, []], [7006, ['test333']]].each do |port , values|
          redis_obj = double(port)
          allow(redis_obj).to receive(:keys).and_return(values)
          pool_nodes.find {|node| node.instance_variable_get("@options")[:port] == port }.instance_variable_set("@connection", redis_obj)
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

  describe "errors" do
    context "node cluster support disabled" do
      before do
        error = Redis::CommandError.new('ERR This instance has cluster support disabled')
        allow_any_instance_of(Redis).to receive(:cluster).and_raise(error)
      end

      it "raise Redis::CommandError" do
        hosts = [{host: '127.0.0.1', port: '7000'}]
        expect{ RedisCluster::Client.new(hosts) }.to raise_error Redis::CommandError
      end

      it "initializes single node pool when force_cluster is false" do
        hosts = [{host: '127.0.0.1', port: '7000'}]
        @redis = RedisCluster::Client.new(hosts, force_cluster: false)
        expect(pool_hosts).to eq(["127.0.0.1"])
        expect(pool_ports).to eq(["7000"])
      end

      it "retries intermittent errors" do
        cluster_nodes = [
          [0, RedisCluster::Configuration::HASH_SLOTS, ["127.0.0.1", 7000]],
        ]
        allow_any_instance_of(Redis).to receive(:cluster).and_return(cluster_nodes)

        hosts = [{host: '127.0.0.1', port: '7000'}]
        @redis = RedisCluster::Client.new(hosts, retry_count: 1)

        num_invocations = 0
        redis_double = double("Redis connection")
        allow(redis_double).to receive(:get) do
          num_invocations += 1
          raise Redis::CannotConnectError if num_invocations == 1
          "b"
        end
        @redis.instance_variable_get("@pool").nodes.
          each {|node| node.instance_variable_set(:@connection, redis_double)}

        expect(@redis.get("a")).to eq("b")
      end

      it "reraises errors to user after running out of retries" do
        cluster_nodes = [
          [0, RedisCluster::Configuration::HASH_SLOTS, ["127.0.0.1", 7000]],
        ]
        allow_any_instance_of(Redis).to receive(:cluster).and_return(cluster_nodes)

        hosts = [{host: '127.0.0.1', port: '7000'}]
        @redis = RedisCluster::Client.new(hosts, retry_count: 0)

        redis_double = double("Redis connection")
        allow(redis_double).to receive(:get).and_raise(Redis::CannotConnectError)
        @redis.instance_variable_get("@pool").nodes.
          each {|node| node.instance_variable_set(:@connection, redis_double)}

        expect{ @redis.get("a") }.to raise_error Redis::CannotConnectError
      end
    end
  end

  describe "#reconnect" do
    it "reconnects clients" do
      # Expect every connection to receive a close
      pool_nodes.each do |node|
        expect(node.connection).to receive(:close)
      end

      @redis.reconnect

      # When reconnecting, the client will reuse the hosts that it received
      # from `CLUSTER SLOTS`. We therefore expect the full range of ports
      # instead of just the ones that we configured originally.
      [7003, 7006, 7002, 7004].each do |port|
        expect(pool_ports).to include port
      end
    end

    it "reconnects clients and uses original hosts configuration" do
      # Expect every connection to receive a close
      pool_nodes.each do |node|
        expect(node.connection).to receive(:close)
      end

      # Currently the client is already loaded with the full set of hosts that
      # stubbed in the global `before` block. Here we restub `Redis` to only
      # return a single host instead. The client will get this result when it
      # reconnects, and that allows us to verify that it's indeed doing a new
      # lookup instead of reusing its previously existing set of hosts.
      cluster_nodes = [
        [0, RedisCluster::Configuration::HASH_SLOTS, ["127.0.0.1", "7000"]],
      ]
      allow_any_instance_of(Redis).to receive(:cluster).and_return(cluster_nodes)

      @redis.reconnect(use_initial_hosts: true)

      # When reconnecting, the client will reuse the hosts that it received
      # from `CLUSTER SLOTS`. We therefore expect the full range of ports
      # instead of just the ones that we configured originally.
      expect(pool_hosts).to eq(["127.0.0.1"])
      expect(pool_ports).to eq(["7000"])
    end
  end

  describe "keys" do
    it "supports a default argument" do
      allow(pool).to receive(:execute).with("keys", ["*"], {:asking=>false, :random_node=>false}).and_return(["abc", "def"])
      result = @redis.keys
      expect(result).to eq(["abc", "def"])
    end
  end
end
