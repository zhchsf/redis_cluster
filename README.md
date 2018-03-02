# RedisCluster

![travis ci](https://travis-ci.org/zhchsf/redis_cluster.svg?branch=master)

Support: Ruby 2.0+

Redis Cluster is a Redis configuration that allows data to be automatically
sharded across a number of different nodes. You can find its main documentation
at https://redis.io/topics/cluster-tutorial.

[`redis-rb`](https://github.com/redis/redis-rb), the most common Redis gem for
Ruby, doesn't offer Redis Cluster support. This gem works in conjunction with
redis-rb to add the missing functionality. It's based on [antirez's prototype
reference implementation](https://github.com/antirez/redis-rb-cluster) (which
is not maintained).

## Installation

Add it to your `Gemfile`:

```ruby
gem 'redis_cluster'
```

## Usage

Initialize `RedisCluster` with an array of Redis Cluster host nodes:

```ruby
rs = RedisCluster.new([
  {host: '127.0.0.1', port: 7000},
  {host: '127.0.0.1', port: 7001}
])
rs.set "test", 1
rs.get "test"
```

The library will issue the `CLUSTER SLOTS` command to configured hosts it it
receives a `MOVED` response, so it's safe to configure it with only a subset of
the total nodes in the cluster.

### Other options

Most options are forwarded onto underlying `Redis` clients. If for example
`masterauth` and `requirepass` are enabled, the password can be set like this:

```ruby
RedisCluster.new(hosts, password: 'password')
```

### Standalone Redis

If initialized with a host hash instead of an array, the library will assume
that it's operating on a standalone Redis, and cluster functionality will be
disabled:

```ruby
rs = RedisCluster.new({host: '127.0.0.1', port: 7000})
```

When configured with an array of hosts the library normally requires that they
be part of a Redis Cluster, but that check can be disabled by setting
`force_cluster: false`. This may be useful for development or test environments
where a full cluster isn't available, but where a standalone Redis will do just
as well.

```ruby
rs = RedisCluster.new([
  {host: '127.0.0.1', port: 7000},
], force_cluster: false)
```

### Logging

A logger can be specified with the `logger` option. It should be compatible
with the interface of Ruby's `Logger` from the standard library.

```ruby
require 'logger'
logger = Logger.new(STDOUT)
logger.level = Logger::WARN
RedisCluster.new(hosts, logger: logger)
```

### `KEYS`

The `KEYS` command will scan all nodes:

```ruby
rs.keys 'test*'
```

### Pipelining, `MULTI`

There is limited support for pipelining and `MULTI`:

```ruby
rs.pipelined do
  rs.set "{foo}one", 1
  rs.set "{foo}two", 2
end
```

Note that all keys used in a pipeline must map to the same Redis node. This is
possible through the use of Redis Cluster "hash tags" where only the section of
a key name wrapped in `{}` when calculating a key's hash.

#### `EVAL`, `EVALSHA`, `SCRIPT`

`EVAL` and `EVALSHA` must only rely on keys that map to a single slot (again,
possible with hash tags). `KEYS` should be used to retrieve keys in Lua
scripts.

```ruby
rs.eval "return redis.call('get', KEYS[1]) + ARGV[1]", [:test], [3]
rs.evalsha '727fc2fb7c0f11ec134d998654e3dadaacf31a97', [:test], [5]

# Even if a Lua script doesn't need any keys or argvs, you'll still need to
specify a dummy key.
rs.eval "return 'hello redis!'", [:foo]
```

`SCRIPT` commands will run on all nodes:

```ruby
# script commands will run on all nodes
rs.script :load, "return redis.call('get', KEYS[1])"
rs.script :exists, '4e6d8fc8bb01276962cce5371fa795a7763657ae'
rs.script :flush
```

## Development

Clone the repository and then install dependencies:

```sh
bin/setup
```

Run tests:

```sh
rake spec
```

`bin/console` will bring up an interactive prompt for other experimentation.

### Releases

To release a new version, update the version number in `version.rb` and run
`bundle exec rake release`. This will create a Git tag for the version, push
Git commits and tags to GitHub, and push the `.gem` file to Rubygems.

The gem can be installed locally with `bundle exec rake install`.

### Benchmark test

```ruby
Benchmark.bm do |x|
  x.report do
    1.upto(100_000).each do |i|
      redis.set "test#{i}", i
    end
  end
  x.report do
    1.upto(100_000).each do |i|
      redis.get "test#{i}"
    end
  end
  x.report do
    1.upto(100_000).each do |i|
      redis.del "test#{i}"
    end
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub. This project is intended
to be a safe, welcoming space for collaboration, and contributors are expected
to adhere to the [Contributor Covenant](http://contributor-covenant.org) code
of conduct.

## License

The gem is available as open source under the terms of the [MIT
License](http://opensource.org/licenses/MIT).

<!--
# vim: set tw=79:
-->
