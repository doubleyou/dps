-module(bench).

-export([start/0, start/1, stats/0]).

-define(OPTIONS, [
    {clients, 1000},
    {channels, 10},
    {channels_per_client, {1, 2}},
    {pub_interval, 1000},
    {hosts, ["localhost"]}
]).

-define(PORT, 9201).
-define(AVG_SIZE, 36).


-record(state, {
    channels,
    client,
    push_packets,
    poll_packet,
    host,
    ts = 0,
    publish_interval,
    sock
}).

start() ->
    start([]).

stats() ->
    ets:match(stats, '$1').

start(Opts) ->
    Options = Opts ++ ?OPTIONS,

    Clients = proplists:get_value(clients, Options),
    ChPC = proplists:get_value(channels_per_client, Options),
    Channels = [make_channel(I)
        || I <- lists:seq(1, proplists:get_value(channels, Options))],
    Hosts = proplists:get_value(hosts, Options),
    PubInterval = proplists:get_value(pub_interval, Options),
    HL = length(Hosts),

    ets:new(stats, [public, named_table, set]),
    ets:insert(stats, {publishes, 0}),
    ets:insert(stats, {messages, 0}),
    ets:insert(stats, {start_at, erlang:now()}),

    proc_lib:spawn_link(fun stats_collector/0),

    [proc_lib:spawn_link(fun() ->
            client(Channels, ChPC, lists:nth(I rem HL + 1, Hosts), PubInterval, round(PubInterval * I / Clients))
        end)
        || I <- lists:seq(1, Clients)],
    
    ok.

make_channel(I) ->
    lists:concat(["channel_", 10000 + I]).


stats_collector() ->
    timer:sleep(1000),
    [{publishes, PublishCount}] = ets:lookup(stats, publishes),
    [{messages, MessageCount}] = ets:lookup(stats, messages),
    [{start_at, StartAt}] = ets:lookup(stats, start_at),
    _Delta = timer:now_diff(erlang:now(), StartAt) div 1000,
    io:format("~B publish/msec, ~B receive/msec~n", [PublishCount, MessageCount]),
    ets:insert(stats, {publishes, 0}),
    ets:insert(stats, {messages, 0}),
    ets:insert(stats, {start_at, erlang:now()}),
    stats_collector().



client(Channels, {MinChannels, MaxChannels}, Host, Interval, _TimeOffset) ->
    random:seed(now()),
    CL = length(Channels),
    TotalChannels = random:uniform(MaxChannels - MinChannels + 1) + MinChannels - 1,
    ClientChannels = [lists:nth(random:uniform(CL), Channels)
        || _ <- lists:seq(1, TotalChannels)],

    client_init(ClientChannels, Interval, Host).

client_init(Channels, Interval, Host) ->
    State = #state{
        channels = Channels,
        push_packets = push_packets(Channels),
        host = Host,
        publish_interval = Interval
    },
    proc_lib:spawn_link(fun() ->
        publisher_connect(State)
    end),
    start_poll(State).

publisher_connect(State) ->
    {ok, S} = gen_tcp:connect(State#state.host, ?PORT, [{active, false}]),
    publisher_loop(State#state{sock = S}).

publisher_loop(State = #state{publish_interval = Interval}) ->
    timer:sleep(Interval),
    push(State, State#state.push_packets).

push(State, []) ->
    publisher_loop(State);
push(State = #state{sock = S}, [Packet | Rest]) ->
    case gen_tcp:send(S, Packet) of
        ok ->
            ets:update_counter(stats, publishes, 1),
            push(State, Rest);
        {error, _} ->
            {ok, NewSock} = gen_tcp:connect(State#state.host, ?PORT, [binary, {packet, raw}, {active, false}]),
            push(State#state{sock=NewSock}, [Packet | Rest])
    end.


start_poll(#state{channels = Channels, host = Host}) ->
    {ok, C} = cowboy_client:init([]),
    URL = iolist_to_binary(io_lib:format("http://~s:~B/poll?channels=~s&ts=", [Host, ?PORT, string:join(Channels, ",")])),
    poll(C, URL, 0).

poll(C1, URL, LastTS) ->
    T = list_to_binary(integer_to_list(LastTS)),
    {ok, C2} = cowboy_client:request(<<"GET">>, <<URL/binary, T/binary>>, C1),
    {ok, Code, _Headers, C3} = cowboy_client:response(C2),
    Code == 200 orelse throw({invalid_comet_reply,Code,_Headers,C3}),
    {ok, Body, C4} = cowboy_client:response_body(C3),
    TS = case binary:split(Body, <<",">>) of
        [T1, Body1] ->
            ets:update_counter(stats, messages, size(Body1) div ?AVG_SIZE),
            cowboy_http:digits(T1);
        [T1] ->
            cowboy_http:digits(T1)
    end,
    timer:sleep(50),
    poll(C4, URL, TS).




push_packets(Channels) ->
    [iolist_to_binary([<<"POST /push HTTP/1.1\r\nHost: localhost:9201\r\nAccept: application/json\r\nContent-type: application/json\r\nConnection: keepalive\r\nContent-Length:34\r\n\r\n">>, Channel, <<"|y u no love node.js?">>])
%%    [[<<"POST /push HTTP/1.1\r\nUser-Agent: curl/7.19.6 (i386-apple-darwin10.5.0) libcurl/7.19.6 OpenSSL/0.9.8r zlib/1.2.5\r\nHost: localhost:9201\r\nAccept: application/json\r\nContent-Length: 34\r\n\r\n">>, Channel, <<"|y u no love node.js?">>]
        || Channel <- Channels].

