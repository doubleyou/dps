-module(dps_channel_tests).

-compile(export_all).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


dps_channel_test_() ->
  TestFunctions = [F || {F,0} <- ?MODULE:module_info(exports),
                            lists:prefix("test_", atom_to_list(F))],
  {foreach,
    fun setup/0,
    fun teardown/1,
    [{atom_to_list(F), fun ?MODULE:F/0} || F <- TestFunctions]
  }.


setup() ->
  Modules = [dps_channel_sup, dps_channel, dps_util],
  meck:new(Modules, [{passthrough, true}]),
  gen_event:delete_handler(error_logger, error_logger_tty_h, []),
  application:start(dps),
  {Modules}.


teardown({Modules}) ->
  meck:unload(Modules),
  application:stop(dps),
  ok.



test_channel_publish() ->
  dps_channels_manager:create(test_channel),
  meck:expect(dps_util, ts, fun() -> 123456 end),
  ?assertEqual(123456, dps_channel:publish(test_channel, message)),
  ok.

test_channel_get_all_messages() ->
  dps_channels_manager:create(test_channel),
  meck:expect(dps_util, ts, fun() -> 123456 end),
  dps_channel:publish(test_channel, message),
  ?assertEqual({ok, 123456, [message]}, dps_channel:messages(test_channel, undefined)),
  ok.


-endif.
