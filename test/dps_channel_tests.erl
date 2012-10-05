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
  meck:expect(dps_util, ts, fun() -> 1 end),
  dps_channel:publish(test_channel, message1),

  meck:expect(dps_util, ts, fun() -> 2 end),
  dps_channel:publish(test_channel, message2),

  ?assertEqual({ok, 2, [message1, message2]}, dps_channel:messages(test_channel, 0)),
  ok.


test_channel_refetch_new_messages() ->
  dps_channels_manager:create(test_channel),
  meck:expect(dps_util, ts, fun() -> 1 end),
  dps_channel:publish(test_channel, message1),

  meck:expect(dps_util, ts, fun() -> 2 end),
  dps_channel:publish(test_channel, message2),

  meck:expect(dps_util, ts, fun() -> 3 end),
  dps_channel:publish(test_channel, message3),

  meck:expect(dps_util, ts, fun() -> 4 end),
  dps_channel:publish(test_channel, message4),


  ?assertEqual({ok, 4, [message3, message4]}, dps_channel:messages(test_channel, 2)),
  ok.

test_channel_messages_limit() ->
  dps_channels_manager:create(test_channel),
  TotalLimit = dps_channel:messages_limit(),

  [dps_channel:publish(test_channel, {messages, I}) || I <- lists:seq(1, TotalLimit)],
  ?assertMatch({ok, _, Msg} when length(Msg) == TotalLimit, dps_channel:messages(test_channel, 0)),

  dps_channel:publish(test_channel, {messages, TotalLimit + 1}),
  {ok, _, Messages} = dps_channel:messages(test_channel, 0),
  ?assertEqual(TotalLimit, length(Messages)),

  Numbers = [I || {messages, I} <- Messages],
  ?assertEqual(2, lists:min(Numbers)),
  ?assertEqual(TotalLimit + 1, lists:max(Numbers)),
  ok.


test_channel_subscribe() ->
  dps_channels_manager:create(test_channel),
  Timeout = 100,
  Self = self(),
  Child = spawn_link(fun() ->
    dps_channel:subscribe(test_channel),
    receive start -> ok after 1000 -> error(start_timeout) end,
    {dps_msg, test_channel, TS1, [Msg1]} = receive {dps_msg, _, _, _} = R1 -> R1 after Timeout -> error(child_timeout1) end,
    {dps_msg, test_channel, TS2, [Msg2]} = receive {dps_msg, _, _, _} = R2 -> R2 after Timeout -> error(child_timeout2) end,
    {dps_msg, test_channel, TS3, [Msg3]} = receive {dps_msg, _, _, _} = R3 -> R3 after Timeout -> error(child_timeout3) end,
    Self ! {ok, [TS1, TS2, TS3], [Msg1,Msg2,Msg3]},
    ok
  end),

  TS1 = dps_channel:publish(test_channel, msg1),
  TS2 = dps_channel:publish(test_channel, msg2),
  TS3 = dps_channel:publish(test_channel, msg3),
  
  Child ! start,

  receive
    {ok, Timestamps, Messages} -> 
      ?assertEqual([msg1,msg2,msg3], Messages),
      ?assertEqual([TS1,TS2,TS3], Timestamps)
  after
    Timeout -> error(parent_timeout)
  end,

  ok.


test_channel_subscribe_with_old_messages() ->
  dps_channels_manager:create(test_channel),
  TS1 = dps_channel:publish(test_channel, msg1),
  _TS2 = dps_channel:publish(test_channel, msg2),
  TS3 = dps_channel:publish(test_channel, msg3),

  dps_channel:subscribe(test_channel, TS1),

  Timeout = 100,
  receive
    {dps_msg, test_channel, LastTS, Messages} ->
      ?assertEqual(TS3, LastTS),
      ?assertEqual([msg2, msg3], Messages);
    Else ->
      ?debugFmt("else: ~p", [Else]),
      error(strange_message)
  after
    Timeout -> error(parent_timeout)
  end,
  ok.



test_multi_fetch() ->
  dps_channels_manager:create(test_channel1),
  dps_channels_manager:create(test_channel2),
  dps_channels_manager:create(test_channel3),

  Self = self(),
  _Child = spawn_link(fun() ->
    Reply = dps_channel:multi_fetch([test_channel1, test_channel2, test_channel3], 0, 5000),
    Self ! {child, Reply}
  end),

  dps_channel:publish(test_channel1, message1),

  receive
    {child, Reply} ->
      ?assertMatch({ok, _, Messages} when length(Messages) == 1, Reply)
  after
    1000 -> error(parent_timeout)
  end,

  ok.














-endif.
