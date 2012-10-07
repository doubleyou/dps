-module(dps_channel).
-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").
% -ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
% -endif.

-export([start_link/1]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-export([publish/2,
         messages/2,
         unsubscribe/1,
         subscribe/1,
         subscribe/2,
         multi_fetch/2,
         multi_fetch/3,


         prepend_sorted/2,
         messages_newer/2,

         messages_limit/0,
         publish_local/3,
         msgs_from_peers/2]).


-record(state, {
    subscribers = []    :: list(),
    messages = []       :: list(),
    last_ts = 0         :: non_neg_integer(),
    limit               :: non_neg_integer(),
    tag                 :: term()
}).

%%
%% External API
%%

-spec messages_limit() -> non_neg_integer().
messages_limit() ->
    1000.


-spec publish(Tag :: dps:tag(), Msg :: dps:message()) -> TS :: dps:timestamp().
publish(Tag, Msg) ->
    TS = dps_util:ts(),
    gen_server:call(find(Tag), {publish, Msg, TS}),
    rpc:multicall(nodes(), ?MODULE, publish_local, [Tag, Msg, TS]),
    TS.


-spec publish_local(Tag :: dps:tag(), Msg :: dps:message(), TS :: dps:timestamp()) -> ok.
publish_local(Tag, Msg, TS) ->
    try gen_server:call(find(Tag), {publish, Msg, TS})
    catch
        throw:{no_channel, Tag} -> ok
    end.


-spec messages(Tag :: dps:tag(), Timestamp :: dps:timestamp()) -> 
    {ok, TS :: dps:timestamp(), [Message :: term()]}.
messages(Tag, TS) when is_number(TS) ->
    {ok, LastTS, Messages} = gen_server:call(find(Tag), {messages, TS}),
    {ok, LastTS, Messages}.


-spec subscribe(Tag :: dps:tag()) -> Msgs :: non_neg_integer().
subscribe(Tag) ->
    subscribe(Tag, 0).

-spec subscribe(Tag :: dps:tag(), TS :: dps:timestamp()) ->
                                                    Msgs :: non_neg_integer().
subscribe(Tag, TS) ->
    gen_server:call(find(Tag), {subscribe, self(), TS}).


-spec unsubscribe(Tag :: term()) -> ok.
unsubscribe(Tag) ->
    gen_server:call(find(Tag), {unsubscribe, self()}).


-spec find(Tag :: term()) -> Pid :: pid().
find(Tag) ->
    Pid = dps_channels_manager:find(Tag),
    Pid =/= undefined orelse erlang:throw({no_channel,Tag}),
    Pid.


-spec multi_fetch([Tag :: dps:tag()], TS :: dps:timestamp()) ->
    {ok, LastTS :: dps:timestamp(), [Message :: term()]}.
multi_fetch(Tags, TS) ->
    multi_fetch(Tags, TS, 60000).


-spec multi_fetch([Tag :: dps:tag()], TS :: dps:timestamp(),
        Timeout :: non_neg_integer()) ->
            {ok, LastTS :: dps:timestamp(), [Message :: term()]}.
multi_fetch(Tags, TS, Timeout) ->
    [subscribe(Tag, TS) || Tag <- Tags],
    receive
        {dps_msg, _Tag, LastTS, Messages} ->
            [unsubscribe(Tag) || Tag <- Tags],
            receive_multi_fetch_results(LastTS, Messages)
    after
        Timeout ->
            [unsubscribe(Tag) || Tag <- Tags],
            receive_multi_fetch_results(TS, [])
    end.


-spec msgs_from_peers(Tag :: dps:tag(), CallbackPid :: pid()) -> ok.
msgs_from_peers(Tag, CallbackPid) ->
    Pid = dps_channels_manager:find(Tag),
    Pid ! {give_me_messages, CallbackPid},
    ok.

-spec start_link(Tag :: dps:tag()) -> Result :: {ok, pid()} | {error, term()}.
start_link(Tag) ->
    gen_server:start_link(?MODULE, Tag, []).

%%
%% gen_server callbacks
%%

-spec init(Tag :: dps:tag()) -> {ok, #state{}}.
init(Tag) ->
    self() ! replicate_from_peers,
    {ok, #state{tag = Tag, limit = messages_limit()}}.

handle_call({publish, Msg, TS}, {Pid, _}, State = #state{messages = Msgs, limit = Limit,
                                                subscribers = Subscribers, tag = Tag}) ->
    Messages1 = prepend_sorted({TS,Msg}, Msgs),
    Messages = if
        length(Messages1) >= Limit*2 -> lists:sublist(Messages1, Limit);
        true -> Messages1
    end,
    [{LastTS, _}|_] = Messages,
    [Sub ! {dps_msg, Tag, LastTS, [Msg]} || {Sub, _Ref} <- Subscribers, Sub =/= Pid],
    NewState = State#state{messages = Messages, last_ts = LastTS},
    {reply, ok, NewState};

handle_call({subscribe, Pid, TS}, _From, State = #state{messages = Messages, tag = Tag,
                                                subscribers = Subscribers, last_ts = LastTS}) ->
    Ref = erlang:monitor(process, Pid),
    Msgs = messages_newer(Messages, TS),
    if
        length(Msgs) > 0 -> Pid ! {dps_msg, Tag, LastTS, Msgs};
        true -> ok
    end,
    NewState = State#state{subscribers = [{Pid,Ref} | Subscribers]},
    {reply, length(Msgs), NewState};

handle_call({unsubscribe, Pid}, _From, State = #state{subscribers = Subscribers}) ->
    {Delete, Remain} = lists:partition(fun({P,_Ref}) -> P == Pid end, Subscribers),
    [erlang:demonitor(Ref) || {_Pid,Ref} <- Delete],
    {reply, ok, State#state{subscribers = Remain}};

handle_call({messages, TS}, _From, State = #state{last_ts = LastTS, messages = AllMessages}) ->
    Messages = messages_newer(AllMessages, TS),
    {reply, {ok, LastTS, Messages}, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, {unknown_call, _Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(replicate_from_peers, State = #state{tag = Tag}) ->
    rpc:multicall(nodes(), ?MODULE, msgs_from_peers, [Tag, self()]),
    {noreply, State};


handle_info({give_me_messages, Pid}, State = #state{last_ts = LastTS, messages = Messages}) ->
    Pid ! {replication_messages, LastTS, Messages},
    {noreply, State};
handle_info({replication_messages, LastTS, Msgs}, State = #state{messages = Messages,
                                                subscribers = Subscribers}) ->
    [[Sub ! {dps_msg, Msg} || Msg <- Msgs] || {Sub, _Ref} <- Subscribers],
    NewState = State#state{last_ts = LastTS, messages = lists:usort(Messages ++ Msgs) },
    {noreply, NewState};
handle_info({'DOWN', Ref, _, Pid, _}, State = #state{subscribers=Subscribers}) ->
    {noreply, State#state{subscribers = Subscribers -- [{Pid,Ref}]}};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%%
%% Internal functions
%%

-spec receive_multi_fetch_results(LastTS :: non_neg_integer(),
        Messages :: list()) ->
            {ok, LastTS :: non_neg_integer(), Messages :: list()}.
receive_multi_fetch_results(LastTS, Messages) ->
    receive
        {dps_msg, _Tag, LastTS1, Messages1} ->
            receive_multi_fetch_results(LastTS1, Messages ++ Messages1)
    after
        0 ->
            {ok, LastTS, Messages}
    end.


prepend_sorted({TS1,Msg1}, [{TS2,_Msg2}|_] = Messages) when TS1 >= TS2 ->
    [{TS1,Msg1}|Messages];

prepend_sorted({TS,Msg}, []) ->
    [{TS,Msg}];

prepend_sorted({TS1,Msg1}, [{TS2,Msg2}|Messages]) when TS1 < TS2 ->
    [{TS2,Msg2}|prepend_sorted({TS1,Msg1}, Messages)].



messages_newer(Messages, TS) ->
    messages_newer(Messages, TS, []).

messages_newer([{TS1,Msg1}|Messages], TS, Acc) when TS1 > TS ->
    messages_newer(Messages, TS, [Msg1|Acc]);

messages_newer(_Messages, _TS, Acc) ->
    Acc.









