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


handle_info(_Info, #replicator{} = State) ->
  {noreply, State}.


terminate(_,_) -> ok.
