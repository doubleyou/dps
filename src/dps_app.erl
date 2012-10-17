-module(dps_app).
-behaviour(application).

-export([start/2, stop/1]).

%%
%% Application callbacks
%%

start(_StartType, _StartArgs) ->
    Ret = dps_sup:start_link(),
    dps_channels_manager:channels(),
    Ret.

stop(_State) ->
    ok.
