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


         messages_limit/0,
         publish/4,
         msgs_from_peers/2]).



-record(state, {
    subscribers = []    :: list(),
    messages = []       :: list(),
    last_ts,
    limit,
    tag                 :: term()
}).

%%
%% External API
%%

messages_limit() ->
    100.


-spec publish(Tag :: term(), Msg :: term()) -> TS :: non_neg_integer().
publish(Tag, Msg) ->
    TS = dps_util:ts(),
    publish(Tag, Msg, TS, global).



-spec messages(Tag :: term(), Timestamp :: non_neg_integer() | undefined) -> 
    {ok, TS :: non_neg_integer() | undefined, [Message :: term()]}.
messages(Tag, TS) ->
    Pid = dps_channels_manager:find(Tag),
    Pid =/= undefined orelse erlang:error(no_channel),
    {ok, LastTS, Messages} = gen_server:call(Pid, {messages, TS}),
    {ok, LastTS, Messages}.

-spec publish(Tag :: term(), Msg :: term(), TS :: non_neg_integer(),
    Mode :: local | global) -> TS :: non_neg_integer().
publish(Tag, Msg, TS, Mode) ->
    Pid = dps_channels_manager:find(Tag),
    Pid =/= undefined orelse erlang:error(no_channel),
    gen_server:call(Pid, {publish, Msg, TS}),
    Mode =:= global andalso
        rpc:multicall(nodes(), ?MODULE, publish, [Tag, Msg, TS, local]),
    TS.

-spec subscribe(Tag :: term()) -> Msgs :: non_neg_integer().
subscribe(Tag) ->
    subscribe(Tag, undefined).

-spec subscribe(Tag :: term(), TS :: non_neg_integer()) ->
                                                    Msgs :: non_neg_integer().
subscribe(Tag, TS) ->
    Pid = dps_channels_manager:find(Tag),
    Pid =/= undefined orelse erlang:error(no_channel),
    gen_server:call(Pid, {subscribe, self(), TS}).



unsubscribe(Tag) ->
    Pid = dps_channels_manager:find(Tag),
    Pid =/= undefined orelse erlang:error(no_channel),
    gen_server:call(Pid, {unsubscribe, self()}).



-spec multi_fetch([Tag :: term()], TS :: non_neg_integer() | undefined) ->
    {ok, LastTS :: non_neg_integer() | undefined, [Message :: term()]}.
multi_fetch(Tags, TS) ->
    multi_fetch(Tags, TS, 60000).


-spec multi_fetch([Tag :: term()], TS :: non_neg_integer() | undefined, Timeout :: non_neg_integer()) ->
    {ok, LastTS :: non_neg_integer() | undefined, [Message :: term()]}.

multi_fetch(Tags, TS, Timeout) ->
    [subscribe(Tag, TS) || Tag <- Tags],
    receive
        {dps_msg, _Tag, LastTS, Messages} ->
            [unsubscribe(Tag) || Tag <- Tags],
            receive_multi_fetch_results(LastTS, Messages)
    after
        Timeout ->
            [unsubscribe(Tag) || Tag <- Tags],
            receive_multi_fetch_results(undefined, [])
    end.

receive_multi_fetch_results(LastTS, Messages) ->
    receive
        {dps_msg, _Tag, LastTS1, Messages1} ->
            receive_multi_fetch_results(LastTS1, Messages ++ Messages1)
    after
        0 ->
            {ok, LastTS, Messages}
    end.



-spec msgs_from_peers(Tag :: term(), CallbackPid :: pid()) -> ok.
msgs_from_peers(Tag, CallbackPid) ->
    Pid = dps_channels_manager:find(Tag),
    Pid ! {give_me_messages, CallbackPid},
    ok.

-spec start_link(Tag :: term()) -> Result :: {ok, pid()} | {error, term()}.
start_link(Tag) ->
    gen_server:start_link(?MODULE, Tag, []).

%%
%% gen_server callbacks
%%

-spec init(Tag :: term()) -> {ok, #state{}}.
init(Tag) ->
    self() ! replicate_from_peers,
    {ok, #state{tag = Tag, limit = messages_limit()}}.

handle_call({publish, Msg, TS}, {Pid, _}, State = #state{messages = Msgs, limit = Limit,
                                                subscribers = Subscribers, tag = Tag}) ->
    Messages1 = lists:sort([{TS, Msg} | Msgs]),
    Messages = if
        length(Messages1) =< Limit -> Messages1;
        length(Messages1) == Limit + 1 -> tl(Messages1)
    end,
    LastTS = lists:max([T || {T, _} <- Messages]),
    [Sub ! {dps_msg, Tag, LastTS, [Msg]} || {Sub, _Ref} <- Subscribers, Sub =/= Pid],
    NewState = State#state{messages = Messages, last_ts = LastTS},
    {reply, ok, NewState};

handle_call({subscribe, Pid, TS}, _From, State = #state{messages = Messages, tag = Tag,
                                                subscribers = Subscribers, last_ts = LastTS}) ->
    Ref = erlang:monitor(process, Pid),
    Msgs = [Msg || {T,Msg} <- Messages, TS == undefined orelse T > TS],
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
    Messages = if 
        is_number(TS) -> [Msg || {T,Msg} <- AllMessages, T > TS];
        TS == undefined -> [Msg || {_,Msg} <- AllMessages]
    end,
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

