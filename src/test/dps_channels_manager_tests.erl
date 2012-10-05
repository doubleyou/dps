-module(dps_channels_manager_tests).
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).

-ifdef(TEST).

manager_test_() ->
  {foreach,
  fun setup/0,
  fun teardown/1,
  [
    fun test_create/0
  ]}.


setup() ->
  Modules = [dps_channels_manager, dps_channels_sup],
  meck:new(Modules, [{passthrough,true}]),
  {ok, Manager} = gen_server:start_link({local, dps_channels_manager}, dps_channels_manager, [], []),
  unlink(Manager),
  meck:expect(dps_channels_sup, start_channel, fun(Tag) ->
    {ok,Pid} = dps_channel:start_link(Tag),
    % unlink(Pid),
    {ok, Pid}
  end),
  {Modules, Manager}.

teardown({Modules, Manager}) ->
  meck:unload(Modules),
  [begin
    unlink(Pid),
    erlang:exit(Pid, shutdown)
  end || {_,Pid} <- ets:tab2list(dps_channels_manager:table())],
  erlang:exit(Manager, shutdown),
  ok.


test_create() ->
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:create(test_channel)),
  ok.


test_channel_failing() ->
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:create(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:find(test_channel)),
  {ok, Pid} = dps_channels_manager:find(test_channel),
  erlang:exit(Pid, kill),
  gen_server:call(dps_channels_manager, sync_call), % Just for synchronisation
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ok.


-endif.