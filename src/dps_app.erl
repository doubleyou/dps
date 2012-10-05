-module(dps_app).
-behaviour(application).

-export([start/2, stop/1]).

%%
%% Application callbacks
%%

start(_StartType, _StartArgs) ->
    {ok, Pid} = dps_sup:start_link(),
    dps_channels_manager:channels(),
    {ok, Pid}.

stop(_State) ->
    ok.
