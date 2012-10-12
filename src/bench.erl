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

-record(state, {
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

    [proc_lib:spawn_link(fun() ->
            client(Channels, ChPC, lists:nth(I rem HL + 1, Hosts), PubInterval, round(PubInterval * I / Clients))
        end)
        || I <- lists:seq(1, Clients)],
    
    ok.

make_channel(I) ->
    lists:concat(["channel_", 10000 + I]).

client(Channels, {MinChannels, MaxChannels}, Host, Interval, _TimeOffset) ->
    random:seed(now()),
    CL = length(Channels),
    TotalChannels = random:uniform(MaxChannels - MinChannels + 1) + MinChannels - 1,
    ClientChannels = [lists:nth(random:uniform(CL), Channels)
        || _ <- lists:seq(1, TotalChannels)],

    client_init(ClientChannels, Interval, Host).

client_init(Channels, Interval, Host) ->
    State = #state{
        push_packets = push_packets(Channels),
        poll_packet = poll_packet(Channels),
        host = Host,
        publish_interval = Interval
    },
    proc_lib:spawn_link(fun() ->
        publisher_connect(State)
    end),
    client_connect(State).

publisher_connect(State) ->
    {ok, S} = gen_tcp:connect(State#state.host, ?PORT, [{active, false}]),
    publisher_loop(State#state{sock = S}).

publisher_loop(State = #state{publish_interval = Interval}) ->
    timer:sleep(Interval),
    push(State, State#state.push_packets).

client_connect(State) ->
    {ok, S} = gen_tcp:connect(State#state.host, ?PORT, [{active, false}]),
    poll(State#state{sock = S}).

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

poll(State = #state{poll_packet = {Pref, Suff}, ts = TS, sock = S}) ->
    inet:setopts(S, [{packet, http}, {active, false}]),
    P = [Pref, integer_to_list(TS), Suff],
    gen_tcp:send(S, P),
    case gen_tcp:recv(S, 0, 5000) of
        {ok, {http_response, _, 200, _ }} ->
            poll_headers(State, S, -1);
        {error, _Error} ->
            client_connect(State);
        _ ->
            client_connect(State)
    end.

poll_headers(State, S, ContentLength) ->
    case gen_tcp:recv(S, 0, 5000) of
        {ok, {http_header, _, 'Content-Length', _, L}} ->
            poll_headers(State, S, list_to_integer(L));
        {ok, {http_header, _, _, _, _}} ->
            poll_headers(State, S, ContentLength);
        {ok, http_eoh} ->
            inet:setopts(S, [binary, {packet, raw}, {active, false}]),
            case gen_tcp:recv(S, 10000) of
                {ok, B} ->
                    ets:update_counter(stats, messages, size(B) div 36);
                _ ->
                    ok
            end,
            poll(State);
        {error, _Error} ->
            client_connect(State);
        V ->
            exit(V)
    end.

push_packets(Channels) ->
    [iolist_to_binary([<<"POST /push HTTP/1.1\r\nHost: localhost:9201\r\nAccept: application/json\r\nContent-type: application/json\r\nConnection: keepalive\r\nContent-Length:34\r\n\r\n">>, Channel, <<"|y u no love node.js?">>])
%%    [[<<"POST /push HTTP/1.1\r\nUser-Agent: curl/7.19.6 (i386-apple-darwin10.5.0) libcurl/7.19.6 OpenSSL/0.9.8r zlib/1.2.5\r\nHost: localhost:9201\r\nAccept: application/json\r\nContent-Length: 34\r\n\r\n">>, Channel, <<"|y u no love node.js?">>]
        || Channel <- Channels].

poll_packet(Channels) ->
    {iolist_to_binary([<<"GET /poll?channels=">>, string:join(Channels, ","), <<"&ts=">>]), <<" HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n">>}.
