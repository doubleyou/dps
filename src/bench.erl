-module(bench).

-export([start/0, start/1]).

-define(OPTIONS, [
    {clients, 10},
    {channels, 10},
    {channels_per_client, {1, 2}},
    {pub_interval, {1000, 2000}},
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

start(Opts) ->
    Options = Opts ++ ?OPTIONS,

    Clients = proplists:get_value(clients, Options),
    ChPC = proplists:get_value(channels_per_client, Options),
    Channels = [make_channel(I)
        || I <- lists:seq(1, proplists:get_value(channels, Options))],
    Hosts = proplists:get_value(hosts, Options),
    PubInterval = proplists:get_value(pub_interval, Options),
    HL = length(Hosts),

    [proc_lib:spawn_link(fun() ->
            client(Channels, ChPC, lists:nth(I rem HL + 1, Hosts), PubInterval)
        end)
        || I <- lists:seq(1, Clients)],
    
    ok.

make_channel(I) ->
    lists:concat(["channel_", 10000 + I]).

client(Channels, {MinChannels, MaxChannels}, Host, {MinTimeout, MaxTimeout}) ->
    random:seed(now()),
    CL = length(Channels),
    TotalChannels = random:uniform(MaxChannels - MinChannels + 1) + MinChannels - 1,
    Interval = random:uniform(MaxTimeout - MinTimeout + 1) + MinTimeout - 1,
    ClientChannels = [lists:nth(random:uniform(CL), Channels)
        || _ <- lists:seq(1, TotalChannels)],

    client_init(ClientChannels, Interval, Host).

client_init(Channels, Interval, Host) ->
    erlang:send_after(Interval, self(), publish),
    client_connect(#state{
        push_packets = push_packets(Channels),
        poll_packet = poll_packet(Channels),
        host = Host,
        publish_interval = Interval
    }).

client_loop(State) ->
    receive
        publish ->
            push(State)
    after 0 ->
        poll(State)
    end.

client_connect(State) ->
    {ok, S} = gen_tcp:connect(State#state.host, ?PORT, [{active, false}]),
    client_loop(State#state{sock = S}).

push(State = #state{sock = S}) ->
    inet:setopts(S, [{packet, raw}]),
    erlang:send_after(State#state.publish_interval, self(), publish),
    [
        begin
        gen_tcp:send(S, Packet),
        gen_tcp:recv(S, 0, 5000)
        end
            || Packet <- State#state.push_packets
    ],
    client_loop(State).

poll(State = #state{poll_packet = {Pref, Suff}, ts = TS, sock = S}) ->
    inet:setopts(S, [{packet, http}]),
    P = [Pref, integer_to_list(TS), Suff],
    gen_tcp:send(S, P),
    case gen_tcp:recv(S, 0, 5000) of
        {ok, {http_response, _, 200, _ }} ->
            poll_headers(State, S, -1);
        {error, Error} ->
            client_connect(State);
        V ->
            exit(V)
    end.

poll_headers(State, S, ContentLength) ->
    case gen_tcp:recv(S, 0, 5000) of
        {ok, {http_header, _, 'Content-Length', _, L}} ->
            poll_headers(State, S, list_to_integer(L));
        {ok, {http_header, _, _, _, _}} ->
            poll_headers(State, S, ContentLength);
        {ok, http_eoh} ->
            inet:setopts(S, [{packet, raw}]),
            gen_tcp:recv(S, 10000),
            client_loop(State);
        {error, Error} ->
            client_connect(State);
        V ->
            exit(V)
    end.

push_packets(Channels) ->
    [iolist_to_binary([<<"POST /push HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\nContent-Length:36\r\n\r\n">>, Channel, <<"y u no love node.js?">>])
        || Channel <- Channels].

poll_packet(Channels) ->
    {iolist_to_binary([<<"GET /poll?channels=">>, string:join(Channels, ","), <<"&ts=">>]), <<" HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n">>}.
