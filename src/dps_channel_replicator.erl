-module(dps_channel_replicator).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_info/2, terminate/2]).



start_link(Tag) ->
  gen_server:start_link(?MODULE, [Tag], []).


-record(replicator, {
  tag
}).

init([Tag]) ->
  {ok, #replicator{tag = Tag}}.

handle_call(Call, _From, #replicator{} = State) ->
  {reply, {error, {unknown_call, Call}}, State}.


handle_info({message, LastTS1, Msg}, #replicator{tag = Tag} = State) ->
  {LastTS, Messages} = collect_all(LastTS1, [Msg]),
  {Channels, _} = rpc:multicall(nodes(), dps_channel, find, [Tag]),
  [try dps_channel:replicate_messages(Pid, LastTS, Messages)
  catch
    exit:{nodedown,_} -> ok
  end || Pid <- Channels, is_pid(Pid)],
  {noreply, State};

handle_info(_Info, #replicator{} = State) ->

  {noreply, State}.


terminate(_,_) -> ok.


collect_all(LastTS1, Messages) ->
  receive
    {LastTS2, Msg} -> collect_all(LastTS2, [Msg|Messages])
  after
    50 -> {LastTS1, Messages}
  end.
