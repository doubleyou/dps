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
  Modules = [],
  meck:new(Modules, [{passthrough, true}]),
  gen_event:delete_handler(error_logger, error_logger_tty_h, []),
  application:start(dps),
  {Modules}.


teardown({Modules}) ->
  meck:unload(Modules),
  application:stop(dps),
  ok.



test_channel_publish() ->
  dps:new(test_channel),
  ?assertEqual(ok, dps_channel:publish(test_channel, message)),
  ok.

test_channel_receive_published_messages() ->
  dps:new(test_channel),
  dps:subscribe(test_channel),
  dps:publish(test_channel, message1),
  receive
    {dps_msg, test_channel, message1} -> ok
  after
    100 -> error(no_message_received)
  end,

  ok.


test_channel_unsubscribe_dead_clients() ->
  dps:new(test_channel),
  dps:subscribe(test_channel),
  Pid = dps_channel:find(test_channel),
  Pid ! {'DOWN', ref, process, self(), normal},
  gen_server:call(Pid, sync_call),
  dps:publish(test_channel, message1),
  receive
    {dps_msg, test_channel, _} -> error(have_not_unsubscribed)
  after
    10 -> ok
  end, 
  ok.



test_channel_failing() ->
  {test_channel, Pid, _} = dps_channels_manager:create(test_channel),
  ?assertNotEqual(Pid, whereis(dps_channels_manager)),

  erlang:monitor(process, Pid),
  erlang:exit(Pid, kill),
  receive
    {'DOWN', _, _, Pid, _} -> ok
  after 1000 ->
    error(test_timeout)
  end,

  %% We need to make sure that 'DOWN' message reaches manager before our call
  gen_server:call(dps_channels_manager, sync_call),

  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ok.





test5_replication_messages() ->
  dps:new(test_channel),

  meck:expect(dps_util, ts, fun() -> 1 end),
  dps:publish(test_channel, message1),

  meck:expect(dps_util, ts, fun() -> 3 end),
  dps:publish(test_channel, message3),


  Self = self(),
  _Child = spawn_link(fun() ->
    dps:subscribe(test_channel, 3),
    Self ! go_on,
    receive
      Reply -> Self ! {child, Reply}
    after
      1000 -> erlang:error(child_timeout)
    end
  end),

  receive
    go_on -> ok
  after
    1000 -> error(parent1_timeout)
  end,

  Pid = dps_channel:find(test_channel),
  Pid ! {replication_messages, 4, [{2,message2},{4,message4}]},

  receive
    {child, Reply} ->
      ?assertEqual({dps_msg, test_channel, 4, [message2,message4]}, Reply)
  after
    1000 -> error(parent_timeout)
  end,

  ?assertEqual({ok, 4, [message1,message2,message3,message4]}, dps_channel:messages(test_channel,0)),

  ok.










-endif.
