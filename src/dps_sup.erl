-module(dps_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([start_channel/1, stop_channel/1]).
-export([init/1]).

-define(CHILD(M, R), {M, {M, start_link, []}, permanent, 5000, R, [M]}).

%%
%% External API
%%

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


start_channel(Name) ->
  ChannelSpec = {Name, {supervisor, start_link, [?MODULE, {channel,Name}]}, permanent, infinity, supervisor, []},
  {ok, Supervisor} = case supervisor:start_child(dps_channels_sup, ChannelSpec) of
    {ok, SupPid} -> {ok, SupPid};
    {error, {already_started, SupPid}} -> {ok, SupPid}
  end,
  {channel, Pid, _, _} = lists:keyfind(channel, 1, supervisor:which_children(Supervisor)),
  {ok, Pid}.

stop_channel(Name) ->
  supervisor:terminate_child(dps_channels_sup, Name),
  supervisor:delete_child(dps_channels_sup, Name).


%%
%% supervisor callbacks
%%

init({channel, Name}) ->
  {ok, {{one_for_all, 5, 10}, [
    {channel, {dps_channel, start_link, [Name]}, permanent, 5000, worker, [dps_channel]},
    {replicator, {dps_channel_replicator, start_link, [Name]}, permanent, 5000, worker, [dps_channel_replicator]}
  ]}};

init([channels]) ->
  {ok, { {one_for_one, 5, 10}, []} };

init([]) ->
    ChannelsSup = {dps_channels_sup, 
      {supervisor, start_link, [{local, dps_channels_sup}, ?MODULE, [channels]]},
      permanent, infinity, supervisor, []
    },
    ChannelsMgr = {dps_channels_manager, 
      {dps_channels_manager, start_link, []},
      permanent, 5000, worker, [dps_channels_manager]
    },
    {ok, { {one_for_one, 5, 10}, [ChannelsSup, ChannelsMgr]} }.
