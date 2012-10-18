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
         % unsubscribe/1,
         subscribe/1,
         find/1,

         channels_table/0,
         clients_table/0,

         replication_messages/2
         ]).


-record(state, {
    tag                 :: term(),
    replicator          :: pid()
}).


%%
%% External API
%%


-spec channels_table() -> Table::term().
channels_table() -> dps_channels_table.

-spec clients_table() -> Table::term().
clients_table() -> dps_clients_table.


-spec publish(Tag :: dps:tag(), Msg :: dps:message()) -> ok | {error, no_channel}.
publish(Tag, Msg) ->
    case dps_channels_manager:find(Tag) of
        {Tag, _Channel, Repl} ->
            [Pid ! {dps_msg, Tag, Msg} || {_, Pid} <- ets:lookup(dps_channel:clients_table(), Tag)],
            replicate(Repl, Tag, Msg),
            ok;
        undefined ->
            {error, no_channel}
    end.


-spec subscribe(Tag :: dps:tag()) -> Msgs :: non_neg_integer().
subscribe(Tag) ->
    try gen_server:call(find(Tag), {subscribe, self()})
    catch
        Class:Error -> erlang:raise(Class, {dps_error, subscribe, Tag, Error}, erlang:get_stacktrace())
    end.


% -spec unsubscribe(Tag :: term()) -> ok.
% unsubscribe(Tag) ->
%     try gen_server:call(find(Tag), {unsubscribe, self()})
%     catch
%         Class:Error -> erlang:raise(Class, {dps_error, unsubscribe, Tag, Error}, erlang:get_stacktrace())
%     end.


-spec find(Tag :: term()) -> Pid :: pid().
find(Pid) when is_pid(Pid) ->
    Pid;
find(Tag) ->
    case dps_channels_manager:find(Tag) of
        {Tag, Pid, _} -> Pid;
        undefined -> erlang:throw({no_channel,Tag})
    end.


-spec replication_messages(Pid :: pid(), [Message :: dps:message()]) -> ok.
replication_messages(Pid, Messages) ->
    try gen_server:call(Pid, {replication_messages, Messages})
    catch
        Class:Error -> erlang:raise(Class, {dps_error, replication_messages, Error}, erlang:get_stacktrace())
    end.


-spec start_link(Tag :: dps:tag()) -> Result :: {ok, pid()} | {error, term()}.
start_link(Tag) ->
    gen_server:start_link(?MODULE, Tag, []).

%%
%% gen_server callbacks
%%

-spec init(Tag :: dps:tag()) -> {ok, #state{}}.
init(Tag) ->
    put(tag,Tag),
    {ok, #state{tag = Tag}}.

handle_call({subscribe, Pid}, _From, State = #state{tag = Tag}) ->
    erlang:monitor(process, Pid),
    ets:insert(dps_channel:clients_table(), {Tag, Pid}),
    {reply, ok, State};

% handle_call({unsubscribe, Pid}, _From, State = #state{subscribers = Subscribers}) ->
%     T1 = erlang:now(),
%     {Delete, Remain} = lists:partition(fun({P,_Ref}) -> P == Pid end, Subscribers),
%     [erlang:demonitor(Ref) || {_Pid,Ref} <- Delete],
%     NewState = State#state{subscribers = Remain},
%     T2 = erlang:now(),
%     put(unsubscribe_count,get(unsubscribe_count)+1),
%     put(unsubscribe_time,get(unsubscribe_time)+timer:now_diff(T2,T1)),
%     {reply, ok, NewState};

handle_call({replication_messages, Messages}, _From, #state{tag = Tag} = State) ->
    Pids = [Pid || {_, Pid} <- ets:lookup(dps_channel:clients_table(), Tag)],
    [Pid ! {dps_msg, Tag, Msg} || Pid <- Pids, Msg <- Messages],
    {reply, ok, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, {unknown_call, _Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info({'DOWN', _Ref, _, Pid, _}, State = #state{tag = Tag}) ->
    MS = ets:fun2ms(fun({Tag_, Pid_}) -> Tag_ == Tag andalso Pid_ == Pid end),
    ets:select_delete(dps_channel:clients_table(), MS),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%%
%% Internal functions
%%


replicate(Replicator, Tag, Msg) ->
    case erlang:process_info(Replicator, message_queue_len) of
        {message_queue_len, QueueLen} when QueueLen > 100 ->
            % gen_server:call(Replicator, {message, LastTS, {TS, Msg}});
            % for now we just skip messages, if replicator is too slow
            ok;
        undefined ->
            ok;
        _ ->
            Replicator ! {dps_msg, Tag, Msg}
    end.



