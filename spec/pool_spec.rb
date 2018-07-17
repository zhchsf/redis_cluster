require 'spec_helper'

describe "pool" do
  before :each do
    @pool = RedisCluster::Pool.new
  end

  shared_examples "slots include" do |slot|
    it "has slot #{slot}" do
      expect( @pool.nodes.any? {|n| n.has_slot? slot} ).to be_truthy
    end
  end

  shared_examples "slots exclude" do |slot|
    it "has not slot #{slot}" do
      expect( @pool.nodes.any? {|n| n.has_slot? slot} ).to_not be_truthy
    end
  end

  describe "nodes operations" do
    let(:node_size) { @pool.nodes.size }

    before :each do
      nodes = [
        [{host: '127.0.0.1', port: 7000}, [1..1000]],
        [{host: '127.0.0.1', port: 7001}, [1001..2000]]
      ]
      nodes.each do |node, slots|
        @pool.add_node!(node, slots)
      end
    end

    describe "#add_node!" do
      context "when add exist host and same slots" do
        before :each do
          @pool.add_node!({host: '127.0.0.1', port: 7000}, [1..1000])
        end

        it "has 2 nodes" do
          expect(node_size).to eq 2
        end

        it_behaves_like "slots include", 888

        it_behaves_like "slots exclude", 8888
      end

      context "when add exist host but more slots" do
        before :each do
          @pool.add_node!({host: '127.0.0.1', port: 7000}, [1..1000, 2001..3001])
        end

        it "has 2 nodes" do
          expect(node_size).to eq 2
        end

        it_behaves_like "slots include", 111

        it_behaves_like "slots include", 2111

        it_behaves_like "slots include", 1888

        it_behaves_like "slots exclude", 3888
      end

      context "when add new host" do
        before :each do
          @pool.add_node!({host: '127.0.0.1', port: 7002}, [4001..5000])
        end

        it "has 3 nodes" do
          expect(node_size).to eq 3
        end

        it_behaves_like "slots include", 5000

        it_behaves_like "slots exclude", 5555
      end
    end

    describe "#delete_except!" do
      before :each do
        now_master_hosts = [['127.0.0.1', 7000], ['127.0.0.1', 7003]]
        @pool.delete_except!(now_master_hosts)
      end

      it "has 1 nodes" do
        expect(node_size).to eq 1
      end

      it_behaves_like "slots include", 888

      it_behaves_like "slots exclude", 1888
    end

    describe "scan" do
      # First iteration, finds one element from the first node and reports there is more to scan...
      it "returns an expanded cursor for the same node when scan returns a nonzero value" do
        allow(@pool.nodes.first).to receive(:execute).with("scan", ["0", {}]).and_return(["2", ["abc"]])

        cursor, keys = @pool.execute(:scan, ["0", {}], {})

        # There are two nodes in the pool, so the scan cursor is doubled...
        expect(cursor).to eq "4"
        expect(keys).to eq ["abc"]
      end

      # Second iteration, using the cursor from before, returns the last element from the first node...
      it "returns a cursor that points to the next node when scan returns a zero value" do
        allow(@pool.nodes.first).to receive(:execute).with("scan", ["2", {}]).and_return(["0", ["def"]])

        cursor, keys = @pool.execute(:scan, ["4", {}], {})

        # Hitting the zero element on the second pool.
        expect(cursor).to eq "1"
        expect(keys).to eq ["def"]
      end

      # Third iteration, using the previously returned cursor.  Returns an element from the second node and reports more to scan
      it "selects the correct node based on the passed cursor" do
        allow(@pool.nodes.last).to receive(:execute).with("scan", ["0", {}]).and_return(["1", ["ghi"]])

        cursor, keys = @pool.execute(:scan, ["1", {}], {})

        # Hitting the zero element on the second pool.
        expect(cursor).to eq "3"
        expect(keys).to eq ["ghi"]
      end

      # Third iteration, using the previously returned cursor.  Returns the last element from the second node
      it "reports zero when the last element on the last node is scanned" do
        allow(@pool.nodes.last).to receive(:execute).with("scan", ["1", {}]).and_return(["0", ["jkl"]])

        cursor, keys = @pool.execute(:scan, ["3", {}], {})

        # Hitting the zero element on the second pool.
        expect(cursor).to eq "0"
        expect(keys).to eq ["jkl"]
      end
    end
  end

end
