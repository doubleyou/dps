-module(dps_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([start_channel/1,
         start_session/1,
         channel_replicator/1,
         stop_channel/1]).
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
  % {channel, Pid, _, _} = lists:keyfind(channel, 1, supervisor:which_children(Supervisor)),
  {ok, Supervisor}.

start_session(Name) ->
  SessionSpec = {Name, {dps_session, start_link, [Name]}, transient, 5000, worker, [dps_session]},
  case supervisor:start_child(dps_sessions_sup, SessionSpec) of
    {ok, P} -> {ok, P};
    {error, {already_started, P}} -> {ok, P}
  end.

channel_replicator(Name) ->
  case lists:keyfind(Name, 1, supervisor:which_children(dps_channels_sup)) of
    {Name, Sup, _, _} ->
      {replicator, Repl, _, _} = lists:keyfind(replicator, 1, supervisor:which_children(Sup)),
      {ok, Repl};
    false ->
      undefined
  end.


stop_channel(Name) ->
  supervisor:terminate_child(dps_channels_sup, Name),
  supervisor:delete_child(dps_channels_sup, Name).


%%
%% supervisor callbacks
%%

init({channel, Name}) ->
  {ok, {{one_for_all, 5, 10}, [
    {replicator, {dps_channel_replicator, start_link, [Name]}, permanent, 5000, worker, [dps_channel_replicator]},
    {channel, {dps_channel, start_link, [Name]}, permanent, 5000, worker, [dps_channel]}
  ]}};

init([sessions]) ->
  {ok, { {one_for_one, 5, 10}, []} };

init([channels]) ->
  {ok, { {one_for_one, 5, 10}, []} };

init([]) ->
    ChannelsSup = {dps_channels_sup, 
      {supervisor, start_link, [{local, dps_channels_sup}, ?MODULE, [channels]]},
      permanent, infinity, supervisor, dynamic
    },
    ChannelsMgr = {dps_channels_manager, 
      {dps_channels_manager, start_link, []},
      permanent, 5000, worker, [dps_channels_manager]
    },
    SessionsSup = {dps_sessions_sup, 
      {supervisor, start_link, [{local, dps_sessions_sup}, ?MODULE, [sessions]]},
      permanent, infinity, supervisor, dynamic
    },
    SessionsMgr = {dps_sessions_manager, 
      {dps_sessions_manager, start_link, []},
      permanent, 5000, worker, [dps_sessions_manager]
    },
    {ok, { {one_for_one, 5, 10}, [ChannelsSup, ChannelsMgr, SessionsSup, SessionsMgr]} }.
