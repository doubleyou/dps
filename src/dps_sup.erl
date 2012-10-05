-module(dps_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(M, R), {M, {M, start_link, []}, permanent, 5000, R, [M]}).

%%
%% External API
%%

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%
%% supervisor callbacks
%%

init([]) ->
    ChannelsMgr = ?CHILD(dps_channels_manager, worker),
    ChannelsSup = ?CHILD(dps_channels_sup, supervisor),
    {ok, { {one_for_one, 5, 10}, [ChannelsSup, ChannelsMgr]} }.
