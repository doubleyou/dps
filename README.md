DPS - Distributed Pub/Sub
=========================

Multichannel distributed pub/sub messaging, with full duplication across several nodes.


Usage:

# Channel creation


    dps:create(<<"channel1">>),
    dps:create(<<"channel2">>).


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




TODO:
=====

* Replace lists with a priority queue implementation
* Add tests (ideally - integration tests)
* Add more robust nodes discovering
* Add docs and specs
* Add channels closing support
* Compare to replicated redis pub/sub
