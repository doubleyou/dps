-module(dps_channels_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).
-export([start_channel/1, stop_channel/1]).

%%
%% External API
%%

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).


start_channel(Name) ->
  ChannelSpec = {Name, {dps_channel, start_link, [Name]}, transient, 5000, worker, [dps_channel]},
  case supervisor:start_child(dps_channels, ChannelSpec) of
    {ok, Pid} -> {ok, Pid};
    {error, {already_started, Pid}} -> {ok, Pid}
  end.

stop_channel(Name) ->
  supervisor:terminate_child(dps_channels, Name),
  supervisor:delete_child(dps_channels, Name).



%%
%% supervisor callbacks
%%

init([channels]) ->
  {ok, {{one_for_one, 5, 10}, []}};


init([]) ->

    ChannelsSup = {dps_channels, 
      {supervisor, start_link, [{local, dps_channels}, ?MODULE, [channels]]},
      permanent,
      infinity,
      supervisor,
      []
    },
    {ok, { {one_for_one, 5, 10}, [ChannelsSup]} }.
