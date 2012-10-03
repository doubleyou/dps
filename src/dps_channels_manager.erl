-module(dps_channels_manager).
-behaviour(gen_server).

-include_lib("stdlib/include/ms_transform.hrl").

-export([start_link/0]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-export([register_channel/2]).

%%
%% External API
%%

start_link() ->
    ets:new(dps_channels, [public, named_table, set]),
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

register_channel(Tag, Pid) ->
    gen_server:call(?MODULE, {register, Tag, Pid}).

%%
%% gen_server callbacks
%%

init(Args) ->
    {ok, Args}.

handle_call({register, Tag, Pid}, _From, State) ->
    ets:insert(dps_channels, {Tag, Pid}),
    erlang:monitor(process, Pid),
    {reply, ok, State};
handle_call(_Msg, _From, State) ->
    {noreply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _, _, Pid, _}, State) ->
    MS = ets:fun2ms(fun({_, Pid_}) -> Pid_ =:= Pid end),
    ets:select_delete(dps_channels, MS),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
