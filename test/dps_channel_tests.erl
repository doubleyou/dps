-module(dps_channel_tests).

-compile(export_all).
-include_lib("eunit/include/eunit.hrl").



dps_channel_test_() ->
  {foreach,
  fun setup_dps_channel/0,
  fun teardown_dps_channel/1,
  [
    fun simple_pub_sup/0
  ]}.


setup_dps_channel() ->
  process_flag(trap_exit, true),
  Modules = [dps_channel_sup, dps_channel],
  {ok, MgrPid} = dps_channels_manager:start_link(),
  meck:new(Modules, [{passthrough, true}]),
  {ok, Pid} = dps_channel:start_link(test_chan),
  Table = ets:new(test_channels, [public, set]),
  meck:expect(dps_channel, table, fun() -> Table end),
  ets:insert(Table, {test_chan, Pid}),
  {Modules, Pid, MgrPid, Table}.


teardown_dps_channel({Modules, Pid, MgrPid, Table}) ->
  meck:unload(Modules),
  ets:delete(Table),
  erlang:exit(Pid, shutdown),
  erlang:exit(MgrPid, shutdown),
  ok.



simple_pub_sup() ->
  ok.
