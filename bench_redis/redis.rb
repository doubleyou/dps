#!/usr/bin/env ruby

require 'rubygems'
require 'redis'
require 'json'

$redis = Redis.new

msg = (1..512).to_a.to_json

i = 1
t1 = Time.now
loop do
  $redis.publish "test_channel", msg
  i = i+1
  if i % 10000 == 0
    delta = Time.now - t1
    if delta > 0
      puts "#{(i / delta).round} msg/s"
    end
  end
end