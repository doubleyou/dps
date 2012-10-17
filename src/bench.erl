-module(bench).

-export([start/0, start/1, stats/0]).
-compile(export_all).

-define(OPTIONS, [
    {clients, 2000},
    {channels, 40},
    {channels_per_client, {1, 4}},
    {pub_interval, 400},
    {hosts, ["localhost"]}
]).


% OutRate = Clients*1000 / PubInterval

% ClientCount * ((MaxChannel + MinChannel)/2) / PubInterval = Messages/MSec
% MessagesPerChannelPerSec = ClientCount * ((MaxChannel + MinChannel)/2)*1000 / (Channels*PubInterval)
% InRate = MessagesPerChannelPerSec*Clients

-define(PORT, 9201).
-define(AVG_SIZE, 36).


-record(state, {
    channels,
    client,
    host,
    ts = 0,
    publish_interval,
    sock,
    session
}).

start() ->
    try start([])
    catch
        Class:Error -> io:format("bench:start failure: ~p:~p~n~p~n", [Class, Error, erlang:get_stacktrace()])
    end.

stats() ->
    ets:match(stats, '$1').

start(Opts) ->
    Options = Opts ++ ?OPTIONS,

    Clients = proplists:get_value(clients, Options),
    {MinChannels,MaxChannels} = proplists:get_value(channels_per_client, Options),
    Channels = [make_channel(I)
        || I <- lists:seq(1, proplists:get_value(channels, Options))],
    Hosts = proplists:get_value(hosts, Options),
    PubInterval = proplists:get_value(pub_interval, Options),

    ets:new(stats, [public, named_table, set]),
    ets:insert(stats, {publishes, 0}),
    ets:insert(stats, {total_publishes, 0}),
    ets:insert(stats, {messages, 0}),
    ets:insert(stats, {total_messages, 0}),
    ets:insert(stats, {timeouts, 0}),
    ets:insert(stats, {start_at, erlang:now()}),

    proc_lib:spawn_link(fun stats_collector/0),

    _Publishers = [proc_lib:spawn_link(fun() ->
        timer:sleep(PubInterval*I div Clients),
        PublishChannels = ["main"|select_random(Channels, MinChannels, MaxChannels)],
        Host = lists:nth(I rem length(Hosts) + 1, Hosts),
        try start_push(#state{channels = PublishChannels, host = Host, publish_interval = PubInterval})
        catch
            Class:Error ->
                io:format("Problems in pusher(~B): ~p:~p~n~p~n", [I,Class,Error, erlang:get_stacktrace()])
        end
    end) || I <- lists:seq(1, Clients)],

    _Pollers = [proc_lib:spawn_link(fun() ->
        timer:sleep(PubInterval*I div Clients),
        PublishChannels = ["main"|select_random(Channels, MinChannels, MaxChannels)],
        Host = lists:nth(I rem length(Hosts) + 1, Hosts),
        start_poll(#state{channels = PublishChannels, host = Host, publish_interval = PubInterval, session = dps_uuid:gen()})
    end) || I <- lists:seq(1, Clients div 40)],
    % Node = node1@squeeze64,
    % pong = net_adm:ping(Node),
    % [rpc:call(Node, dps, new, [list_to_binary(Chan)]) || Chan <- Channels],
    % _Subscribers = [proc_lib:spawn_link(fun() ->
    %     timer:sleep(PubInterval*I div Clients),
    %     PollChannels = select_random(Channels, MinChannels, MaxChannels),
    %     try start_subscribe([list_to_binary(Chan) || Chan <- PollChannels], Node)
    %     catch
    %         Class:Error ->
    %             io:format("Problems in subscriber(~B): ~p:~p~n~p~n", [I,Class,Error, erlang:get_stacktrace()])
    %     end
    % end) || I <- lists:seq(1,Clients div 40)],
    ok.

select_random(Channels,Min,Max) ->
    ChannelCount = crypto:rand_uniform(Min, Max+1),
    select_random(Channels, ChannelCount).

select_random(_Channels, 0) -> 
    [];
select_random(Channels, Count) ->
    N = crypto:rand_uniform(1,length(Channels)+1),
    Channels1 = lists:sublist(Channels,N-1) ++ lists:sublist(Channels,N+1,length(Channels)),
    [lists:nth(N,Channels)|select_random(Channels1,Count-1)].

make_channel(I) ->
    lists:concat(["channel_", 10000 + I]).


stats_collector() ->
    timer:sleep(1000),
    [{publishes, PublishCount}] = ets:lookup(stats, publishes),
    [{_, TotalPublishCount}] = ets:lookup(stats, total_publishes),
    [{messages, MessageCount}] = ets:lookup(stats, messages),
    [{_, TotalMessageCount}] = ets:lookup(stats, total_messages),
    [{start_at, StartAt}] = ets:lookup(stats, start_at),
    _Delta = timer:now_diff(erlang:now(), StartAt) div 1000,
    io:format("~6B publish (~7B), ~6B receive (~7B)~n", [PublishCount, TotalPublishCount, MessageCount, TotalMessageCount]),
    ets:insert(stats, {publishes, 0}),
    ets:insert(stats, {messages, 0}),
    ets:insert(stats, {start_at, erlang:now()}),
    stats_collector().



start_subscribe(Channels, Node) ->
    Pids = [rpc:call(Node, dps_channel, find, [Chan]) || Chan <- Channels],
    [dps_channel:subscribe(Pid) || Pid <- Pids],
    subscribe().

subscribe() ->
    receive
        {dps_msg, _, _, Messages} ->
            ets:update_counter(stats, messages, length(Messages)),
            ets:update_counter(stats, total_messages, length(Messages)),
            subscribe();
        Else ->
            io:format("Unknown message ~p in subscriber~n", [Else])
    end.



start_push(#state{channels = Channels, host = Host, publish_interval = Interval} = State) ->
    URL = iolist_to_binary(io_lib:format("http://~s:~B/push", [Host, ?PORT])),
    {ok, C} = cowboy_client:init([]),
    try push(C, URL, [list_to_binary(Chan) || Chan <- Channels], Interval)
    catch
        error:{badmatch,{error,timeout}} ->
            ets:update_counter(stats, timeouts, 1),
            timer:sleep(500),
            start_push(State);
        error:{badmatch,{error,closed}} ->
            start_push(State)
    end.

push(C1, URL, [Chan|Channels], Interval) ->
    {ok,C2} = cowboy_client:request(<<"POST">>, URL, [], <<Chan/binary, "|y u no love node.js?">>, C1),
    {ok, Code, _Headers, C3} = cowboy_client:response(C2),
    Code == 200 orelse throw({invalid_push_response,Code,_Headers, C3}),
    {done, C4} = cowboy_client:skip_body(C3),

    % httpc:request(post, {URL, [], "text/plain", Chan ++ "|y u no love node.js?"}, [{timeout, 3000}], [], push_httpc),
    ets:update_counter(stats, publishes, 1),
    ets:update_counter(stats, total_publishes, 1),
    timer:sleep(Interval),
    push(C4, URL, Channels ++ [Chan], Interval).


start_poll(#state{channels = Channels, host = Host, session = Session} = State) ->
    {ok, C} = cowboy_client:init([]),
    URL = iolist_to_binary(io_lib:format("http://~s:~B/poll?channels=~s&session=~s", 
        [Host, ?PORT, string:join(Channels, ","),Session])),
    try poll(C, URL)
    catch
        error:{badmatch,{error,closed}} ->
            start_poll(State)
    end.


poll(C1, URL) ->
    {ok, C2} = cowboy_client:request(<<"GET">>, URL, C1),
    {ok, Code, _Headers, C3} = cowboy_client:response(C2),
    Code == 200 orelse throw({invalid_comet_reply,Code,_Headers,C3}),
    {ok, Body, C4} = cowboy_client:response_body(C3),
    ets:update_counter(stats, messages, size(Body) div ?AVG_SIZE),
    ets:update_counter(stats, total_messages, size(Body) div ?AVG_SIZE),
    timer:sleep(100),
    poll(C4, URL).



