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



         publish/4,
         subscribe/1,
         subscribe/2,
         msgs_from_peers/2]).



-record(state, {
    subscribers = []    :: list(),
    messages = []       :: list(),
    last_ts,
    tag                 :: term()
}).

%%
%% External API
%%

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
    subscribe(Tag, 0).

-spec subscribe(Tag :: term(), TS :: non_neg_integer()) ->
                                                    Msgs :: non_neg_integer().
subscribe(Tag, TS) ->
    Pid = dps_channels_manager:find(Tag),
    Pid =/= undefined orelse erlang:error(no_channel),
    gen_server:call(Pid, {subscribe, self(), TS}).


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
    {ok, #state{tag = Tag}}.

handle_call({publish, Msg, TS}, {Pid, _}, State = #state{messages = Msgs,
                                                subscribers = Subscribers}) ->
    [Sub ! {dps_msg, Msg} || Sub <- Subscribers, Sub =/= Pid],
    Messages = lists:sort([{TS, Msg} | Msgs]),
    LastTS = lists:max([T || {T, _} <- Messages]),
    NewState = State#state{messages = Messages, last_ts = LastTS},
    {reply, ok, NewState};

handle_call({subscribe, Pid, TS}, _From, State = #state{messages = Messages,
                                                subscribers = Subscribers}) ->
    erlang:monitor(process, Pid),
    Msgs = later_than(TS, Messages),
    [Pid ! {dps_msg, Msg} || Msg <- Msgs],
    NewState = State#state{subscribers = [Pid | Subscribers]},
    {reply, length(Msgs), NewState};

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


handle_info({give_me_messages, Pid}, State = #state{messages = Messages}) ->
    Pid ! {messages, Messages},
    {noreply, State};
handle_info({messages, Msgs}, State = #state{messages = Messages,
                                                subscribers = Subscribers}) ->
    [[Sub ! {dps_msg, Msg} || Msg <- Msgs] || Sub <- Subscribers],
    NewState = State#state{ messages = lists:usort(Messages ++ Msgs) },
    {noreply, NewState};
handle_info({'DOWN', _, _, Pid, _}, State = #state{subscribers=Subscribers}) ->
    {noreply, State#state{subscribers = Subscribers -- [Pid]}};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%%
%% Internal functions
%%

-spec later_than(TS :: non_neg_integer(), Messages :: list()) -> Msgs :: list().
later_than(TS, Messages) ->
    lists:takewhile(
        fun({TS_, _}) ->
            TS_ > TS
        end,
        Messages
    ).
