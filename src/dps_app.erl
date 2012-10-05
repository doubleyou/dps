-module(dps_app).
-behaviour(application).

-export([start/2, stop/1]).

%%
%% Application callbacks
%%

start(_StartType, _StartArgs) ->
    {ok, Pid} = dps_sup:start_link(),
    % {TagsLists, _} = rpc:multicall(nodes(), dps_channel, all, []),
    % Tags = sets:to_list(sets:from_list(lists:flatten(TagsLists))),
    % [dps:new(Tag) || Tag <- Tags],
    {ok, Pid}.

stop(_State) ->
    ok.
