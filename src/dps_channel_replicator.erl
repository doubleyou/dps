-module(dps_channel_replicator).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_info/2, terminate/2]).


-define(REPLICATION_LAG, 50).


start_link(Tag) ->
  gen_server:start_link(?MODULE, [Tag], []).


-record(replicator, {
  tag
}).

init([Tag]) ->
  {ok, #replicator{tag = Tag}}.

handle_call({message, LastTS1, Msg}, _From, #replicator{} = State) ->
  {reply, ok, handle_message({message, LastTS1, Msg}, State)};

handle_call(Call, _From, #replicator{} = State) ->
  {stop, {unknown_call, Call}, State}.


handle_info({dps_msg, _Tag, Msg}, #replicator{} = State) ->
  NewState = handle_message(Msg, State),
  {noreply, NewState};

handle_info(_Info, #replicator{} = State) ->
  {stop, {unknown_message, _Info}, State}.


terminate(_,_) -> ok.


collect_all(Messages) ->
  receive
    {dps_msg, _Tag, Msg} -> collect_all([Msg|Messages])
  after
    ?REPLICATION_LAG -> lists:reverse(Messages)
  end.


handle_message(Msg, #replicator{tag = Tag} = State) ->
  Messages = collect_all([Msg]),
  {Channels, _} = rpc:multicall(nodes(), dps_channel, find, [Tag]),
  [try dps_channel:replication_messages(Pid, Messages)
  catch
    exit:{nodedown,_} -> ok
  end || Pid <- Channels, is_pid(Pid)],
  State.
