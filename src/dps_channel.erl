-module(dps_channel).
-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([start_link/1]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-export([publish/2,
         publish/4,
         subscribe/1,
         subscribe/2,
         msgs_from_peers/2]).



-record(state, {
    subscribers = [],
    messages = [],
    tag
}).

%%
%% External API
%%

% very convenient function to mock global table when testing



publish(Tag, Msg) ->
    TS = dps_util:ts(),
    publish(Tag, Msg, TS, global).

publish(Tag, Msg, TS, Mode) ->
    Pid = dps_channels_manager:find(Tag),
    gen_server:call(Pid, {publish, Msg, TS}),
    Mode =:= global andalso
        rpc:multicall(nodes(), ?MODULE, publish, [Tag, Msg, TS, local]),
    TS.

subscribe(Tag) ->
    subscribe(Tag, 0).

subscribe(Tag, TS) ->
    Pid = dps_channels_manager:find(Tag),
    gen_server:call(Pid, {subscribe, self(), TS}).


msgs_from_peers(Tag, CallbackPid) ->
    Pid = dps_channels_manager:find(Tag),
    Pid ! {give_me_messages, CallbackPid}.

start_link(Tag) ->
    gen_server:start_link(?MODULE, Tag, []).

%%
%% gen_server callbacks
%%

init(Tag) ->
    self() ! replicate_from_peers,
    {ok, #state{tag = Tag}}.

handle_call({publish, Msg, TS}, {Pid, _}, State = #state{messages = Msgs,
                                                subscribers = Subscribers}) ->
    [Sub ! {dps_msg, Msg} || Sub <- Subscribers, Sub =/= Pid],
    NewState = State#state{messages = lists:sort([{TS, Msg} | Msgs])},
    {reply, ok, NewState};
handle_call({subscribe, Pid, TS}, _From, State = #state{messages = Messages,
                                                subscribers = Subscribers}) ->
    erlang:monitor(process, Pid),
    Msgs = later_than(TS, Messages),
    [Pid ! {dps_msg, Msg} || Msg <- Msgs],
    NewState = State#state{subscribers = [Pid | Subscribers]},
    {reply, length(Msgs), NewState};
handle_call(_Msg, _From, State) ->
    {noreply, State}.

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

later_than(TS, Messages) ->
    lists:takewhile(
        fun({TS_, _}) ->
            TS_ > TS
        end,
        Messages
    ).
