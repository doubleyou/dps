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
    all/0]).

-export([channels/0]).

%%
%% External API
%%


-record(chan, {
    tag,
    pid,
    repl
}).


start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


create(Tag) ->
    case find(Tag) of
        undefined ->
            rpc:multicall(?MODULE, create_local, [Tag]),
            find(Tag);
        Info ->
            Info
    end.

create_local(Tag) ->
    gen_server:call(?MODULE, {create, Tag}).


all() ->
    MS = ets:fun2ms(fun(#chan{tag = Tag}) -> Tag end),
    ets:select(dps_channel:channels_table(), MS).


find(Tag) ->
    case ets:lookup(dps_channel:channels_table(), Tag) of
        [#chan{tag = Tag, pid = Pid, repl = Repl}] -> {Tag, Pid, Repl};
        [] -> undefined
    end.

% Synchronous call, duplicating all() choice.
% It is used because manager will reply only after replication is over
channels() ->
    gen_server:call(?MODULE, channels).

%%
%% gen_server callbacks
%%

init(Args) ->
    % Recovery procedure
    ets:new(dps_channel:channels_table(), [public, named_table, set, {keypos, #chan.tag}]),
    ets:new(dps_channel:clients_table(), [public, named_table, bag]),
    self() ! load_from_siblings,    
    {ok, Args}.


handle_info(load_from_siblings, State) ->
    {Replies, _} = rpc:multicall(nodes(), dps_channels_manager, all, []),
    AllTags = lists:usort(lists:flatten(Replies)),
    [inner_create(Tag) || Tag <- AllTags],
    {noreply, State};

handle_info({'DOWN', _, _, Pid, _}, State) ->
    MS = ets:fun2ms(fun(#chan{tag = Tag, pid = Pid_}) when Pid_ == Pid -> Tag end),
    case ets:select(dps_channel:channels_table(), MS) of
        [Name] ->
            ets:delete(dps_channel:channels_table(), Name),
            ets:delete(dps_channel:clients_table(), Name);
        [] ->
            ok
    end,
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.



handle_call(channels, _From, State) ->
    {reply, all(), State};

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
            {ok, Sup} = dps_sup:start_channel(Tag),
            {channel, Pid, _, _} = lists:keyfind(channel, 1, supervisor:which_children(Sup)),
            {replicator, Repl, _, _} = lists:keyfind(replicator, 1, supervisor:which_children(Sup)),

            ets:insert(dps_channel:channels_table(), #chan{tag = Tag, pid = Pid, repl = Repl}),
            erlang:monitor(process, Pid),
            Pid;
        Pid ->
            Pid
    end,
    Reply.

