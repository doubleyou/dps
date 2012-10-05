-module(dps_channels_manager).
-behaviour(gen_server).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

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
    create_local/1,
    all/0,
    table/0]).

%%
%% External API
%%

table() -> dps_channels_manager.


start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


create(Tag) ->
    case find(Tag) of
        {ok, Pid} ->
            {ok, Pid};
        undefined ->
            rpc:multicall(?MODULE, create_local, [Tag]),
            find(Tag)
    end.

create_local(Tag) ->
    gen_server:call(?MODULE, {create, Tag}).


all() ->
    MS = ets:fun2ms(fun({Tag, _}) -> Tag end),
    ets:select(table(), MS).


find(Tag) ->
    case ets:lookup(table(), Tag) of
        [{Tag, Pid}] -> {ok, Pid};
        [] -> undefined
    end.


%%
%% gen_server callbacks
%%

init(Args) ->
    % Recovery procedure
    ets:new(dps_channels_manager:table(), [public, named_table, set]),
    self() ! load_from_siblings,    
    {ok, Args}.


handle_info(load_from_siblings, State) ->
    {Replies, _} = rpc:multicall(nodes(), dps_channels_manager, all, []),
    AllTags = lists:usort(lists:flatten(Replies)),
    [inner_create(Tag) || Tag <- AllTags],
    {noreply, State};

handle_info({'DOWN', _, _, Pid, _}, State) ->
    MS = ets:fun2ms(fun({_, Pid_}) -> Pid_ =:= Pid end),
    ets:select_delete(dps_channels_manager:table(), MS),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.



handle_call({create, Tag}, _From, State) ->
    Reply = inner_create(Tag),
    {reply, Reply, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, {unknown_call, _Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

inner_create(Tag) ->
    % secondary check inside singleton process is mandatory because
    % we need to avoid race condition
    Reply = case find(Tag) of
        undefined ->
            {ok, Pid} = dps_channels_sup:start_channel(Tag),
            ets:insert(dps_channels_manager:table(), {Tag, Pid}),
            erlang:monitor(process, Pid),
            {ok, Pid};
        {ok, Pid} ->
            {ok, Pid}
    end,
    Reply.

