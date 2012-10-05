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
  Modules = [dps_channel_sup, dps_channel],
  meck:new(Modules, [{passthrough, true}]),
  {ok, Pid} = dps_channel:start_link(test_chan),
  unlink(Pid),
  {Modules, Pid}.


teardown_dps_channel({Modules, Pid}) ->
  meck:unload(Modules),
  erlang:exit(Pid, shutdown),
  ok.



simple_pub_sup() ->
  ok.
