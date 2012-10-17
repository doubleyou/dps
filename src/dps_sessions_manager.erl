-module(dps_sessions_manager).
-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").

-export([start_link/0]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-export([
    find/1,
    create/1,
    all/0,
    table/0]).

%%
%% External API
%%

table() -> ?MODULE.


start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


create(Session) ->
    case find(Session) of
        undefined ->
            gen_server:call(?MODULE, {create, Session}),
            find(Session);
        Pid ->
            Pid
    end.

all() ->
    MS = ets:fun2ms(fun({Session, _}) -> Session end),
    ets:select(table(), MS).


find(Session) ->
    case ets:lookup(table(), Session) of
        [{Session, Pid}] -> Pid;
        [] -> undefined
    end.

%%
%% gen_server callbacks
%%

init(Args) ->
    % Recovery procedure
    ets:new(dps_sessions_manager:table(), [public, named_table, set]),
    {ok, Args}.


handle_info({'DOWN', _, _, Pid, _}, State) ->
    MS = ets:fun2ms(fun({_, Pid_}) -> Pid_ =:= Pid end),
    ets:select_delete(dps_sessions_manager:table(), MS),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.



handle_call({create, Session}, _From, State) ->
    Reply = inner_create(Session),
    {reply, Reply, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, {unknown_call, _Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

inner_create(Session) ->
    % secondary check inside singleton process is mandatory because
    % we need to avoid race condition
    Reply = case find(Session) of
        undefined ->
            {ok, Pid} = dps_sup:start_session(Session),
            ets:insert(dps_sessions_manager:table(), {Session, Pid}),
            erlang:monitor(process, Pid),
            Pid;
        Pid ->
            Pid
    end,
    Reply.

