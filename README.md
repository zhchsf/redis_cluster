# RedisCluster

![travis ci](https://travis-ci.org/zhchsf/redis_cluster.svg?branch=master)

First see: [https://redis.io/topics/cluster-tutorial](https://redis.io/topics/cluster-tutorial)

RedisCluster for ruby is rewrited from [https://github.com/antirez/redis-rb-cluster](https://github.com/antirez/redis-rb-cluster)


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis_cluster'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis_cluster

## Usage

First you need to configure redis cluster with some nodes! Please see: [https://redis.io/topics/cluster-tutorial](https://redis.io/topics/cluster-tutorial)

```ruby
# don't need all, gem can auto detect all nodes, and process failover if some master nodes down
hosts = [{host: '127.0.0.1', port: 7000}, {host: '127.0.0.1', port: 7001}]
rs = RedisCluster.new hosts
rs.set "test", 1
rs.get "test"
```

now support keys command with scanning all nodes:
```ruby
rs.keys 'test*'
```

limited support commands: pipelined, multi
```ruby
# you must ensure keys at one solt: use one key or hash tags
# if you don't, not raise any errors now
rs.pipelined do
  rs.set "{foo}one", 1
  rs.set "{foo}two", 2
end
```

## Benchmark test

A simple benchmark at my macbook, start 4 master nodes (and 4 cold slave nodes), running with one ruby process.
This only testing redis_cluster can work, not for redis Performance. When I fork 8 ruby process same time and run get command，redis can run 80,000 - 110,000 times per second at my macbook.


```ruby
Benchmark.bm do |x|
  x.report do
    1.upto(100_000).each do |i|
      redis.get "test#{i}"
    end
  end
  x.report do
    1.upto(100_000).each do |i|
      redis.set "test#{i}", i
    end
  end
  x.report do
    1.upto(100_000).each do |i|
      redis.del "test#{i}"
    end
  end
end
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/zhchsf/redis_cluster. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

