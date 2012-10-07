DPS - Distributed Pub/Sub
=========================

Multichannel distributed pub/sub messaging, with full duplication across several nodes.

Replication has protection from lag: if neighbour is too slow, replication if suspended.

Usage:

# Channel creation


    dps:new(<<"channel1">>),
    dps:new(<<"channel2">>).


# Publishing

    dps:publish(<<"channel1">>, <<"Message1">>).


# Subscribing for WebSockets


    TS = 0,
    dps:subscribe(<<"channel1">>, TS),
    dps:subscribe(<<"channel2">>, TS),
    dps:subscribe(<<"channel3">>, TS),
    receive
      {dps_msg, Channel, LastTS, Messages} -> 
        reply({json, [{ts,LastTS},{messages,Messages}]})
    end.

# Subscribing for long-poll comet

multi_fetch will wait for first message from any requested channel.
Can return immediately with many messages, if your TS is too old
and some messages have arrived after it.

    TS = list_to_integer(proplists:get_value("ts",Query, "0")),
    {ok, LastTS, Messages} = dps:multi_fetch([<<"channel1">>,<<"channel2">>], TS, 30000),
    reply({json, [{ts,LastTS}, {messages,Messages}]}).



Benchmarking
============

DPS is beleived to handle about 60 000 msg/sec on several channels with replicating on several servers.

How to benchmark:

    maxbp:dps max$ make bench
    ./rebar compile skip_deps=true
    ==> dps (compile)
    erl -pa ebin -pa deps/*/ebin -smp enable -s dps_benchmark run1 -sname bench@localhost -setcookie cookie
    Erlang R15B02 (erts-5.9.2) [source] [64-bit] [smp:4:4] [async-threads:0] [hipe] [kernel-poll:false] [dtrace]

    Eshell V5.9.2  (abort with ^G)
    (bench@localhost)1> Send: 0 msg/s
    Send: 31236 msg/s
    Send: 43068 msg/s
    Send: 66458 msg/s
    Send: 54695 msg/s
    Send: 57312 msg/s
    Send: 57570 msg/s
    Send: 57843 msg/s
    Send: 58531 msg/s



You will be able to see how many messages are published inside DPS

Now lets compare with Redis pub/sub w. ruby client:

    maxbp:dps max$ ./bench_redis/redis.rb 
    8710 msg/s
    9043 msg/s
    9063 msg/s
    8971 msg/s
    8972 msg/s
    8885 msg/s
    8852 msg/s


It is not what we are waiting for from C server with replication and without storing messages!



TODO:
=====

* Add more robust nodes discovering
* Add docs
* Add channels closing support
* Compare to replicated redis pub/sub
