-module(dps_channels_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%%
%% External API
%%

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%
%% supervisor callbacks
%%

init([]) ->
    Child = {none, {dps_channel, start_link, []}, transient, 5000, worker, [dps_channel]},
    {ok, { {simple_one_for_one, 5, 10}, [Child]} }.
