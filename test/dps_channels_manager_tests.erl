-module(dps_channels_manager_tests).
-compile(export_all).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


manager_test_() ->
  TestFunctions = [{F,Arity} || {F,Arity} <- ?MODULE:module_info(exports),
                            lists:prefix("test_", atom_to_list(F))],
  {foreach,
    fun setup/0,
    fun teardown/1,
    [case Fun of
      {F,0} -> {atom_to_list(F), fun ?MODULE:F/0};
      {F,1} -> {with, [fun ?MODULE:F/1]}
    end || Fun <- TestFunctions]
  }.

-record(env, {
  modules,
  slaves = []
}).

-define(NODE_COUNT, 4).

setup() ->
  % Modules = [dps_channels_manager, dps_channels_sup],
  % meck:new(Modules, [{passthrough,true}]),
  Modules = [],

  net_kernel:start([dps_test, shortnames]),
  erlang:set_cookie(node(), mytestcookie),
  {ok,Host} = inet:gethostname(),
  Slaves = lists:map(fun(I) ->
    Name = list_to_atom("dps_test" ++ integer_to_list(I)),
    {ok, Slave} = slave:start_link(Host, Name, "-setcookie mytestcookie -pa ebin "),
    {Slave, Host, Name}
  end, lists:seq(1,?NODE_COUNT)),

  application:start(dps),
  gen_event:delete_handler(error_logger, error_logger_tty_h, []),
  #env{modules = Modules, slaves = Slaves}.

teardown(#env{modules = Modules, slaves = Slaves}) ->
  [slave:stop(Slave) || {Slave,_,_} <- Slaves],
  meck:unload(Modules),
  application:stop(dps),
  ?assertEqual([], nodes()),
  ?assertEqual(undefined, whereis(dps_sup)),
  ok.


test_create() ->
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ?assertMatch(Pid when is_pid(Pid), dps_channels_manager:create(test_channel)),
  ok.


test_slaves_are_ready() ->
  ?assertEqual(length(nodes()), ?NODE_COUNT),
  ok.


test_channel_failing() ->
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),

  Pid = dps_channels_manager:create(test_channel),
  ?assertEqual(true, is_pid(Pid)),
  ?assertEqual(Pid, dps_channels_manager:find(test_channel)),
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


test_publish_on_channel() ->
  ?assertMatch(Pid when is_pid(Pid), dps_channels_manager:create(test_channel)),
  ?assertMatch(TS when is_number(TS), dps_channel:publish(test_channel, message)),
  ok.



test_remote_channels_start() ->
  assert_remote_start(),

  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  assert_create(),

  {Replies2, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  RemoteChannels = [Pid || Pid <- Replies2, is_pid(Pid)],
  ?assertEqual([], BadNodes2),
  ?assertEqual(?NODE_COUNT, length(RemoteChannels)),
  ok.


test_remote_slaves_take_our_channels_on_start() ->
  assert_create(),
  assert_remote_start(),

  {Replies, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  RemoteChannels = [Pid || Pid <- Replies, is_pid(Pid)],
  ?assertEqual([], BadNodes2),
  ?assertEqual(?NODE_COUNT, length(RemoteChannels)),
  ok.



test_remote_channels_take_our_history_on_start() ->
  assert_create(),
  [dps_channel:publish(test_channel, N) || N <- lists:seq(1,100)],
  ?assertMatch({ok, TS, Messages} when is_number(TS) andalso length(Messages) == 100, dps_channel:messages(test_channel, 0)),
  assert_remote_start(),

  {Replies, BadNodes2} = rpc:multicall(nodes(), dps_channel, messages, [test_channel, 0]),
  ?assertEqual([], BadNodes2),
  [Reply|_] = Replies,

  ?assertMatch({ok, TS, Messages} when is_number(TS) andalso length(Messages) == 100, Reply),
  ok.

assert_create() ->
  ?assertMatch(Pid when is_pid(Pid), dps_channels_manager:create(test_channel)).

assert_remote_start() ->
  {ok, [AppDesc]} = file:consult("../ebin/dps.app"),
  rpc:multicall(nodes(), application, load, [AppDesc]),
  ?assertMatch({_,[]}, rpc:multicall(nodes(), application, start, [dps])).



test_replication_publish_when_node_is_not_initialized() ->
  assert_create(),
  [?assertMatch(TS when is_number(TS), dps_channel:publish(test_channel, N)) || N <- lists:seq(1,100)],
  ok.  



test_node_refill_history_after_restart(#env{slaves = Slaves}) ->
  ?assertMatch(Pid when is_pid(Pid), dps_channels_manager:create(chan1)),
  ?assertMatch(Pid when is_pid(Pid), dps_channels_manager:create(chan2)),

  assert_remote_start(),

  ChannelLimit = dps_channel:messages_limit(),


  [dps_channel:publish(chan1, N) || N <- lists:seq(1,4*ChannelLimit)],
  [dps_channel:publish(chan2, N) || N <- lists:seq(1,4*ChannelLimit)],

  {Slave, Host, Name} = hd(Slaves),

  ?assertMatch({ok, _, Messages} when length(Messages) < 2*ChannelLimit, rpc:call(Slave, dps_channel, messages, [chan1, 0])),

  slave:stop(Slave),
  {ok, Slave} = slave:start_link(Host, Name, "-setcookie mytestcookie -pa ebin "),
  {ok, [AppDesc]} = file:consult("../ebin/dps.app"),
  rpc:call(Slave, application, load, [AppDesc]),
  ?assertEqual(ok, rpc:call(Slave, application, start, [dps])),
  ?assertMatch({ok, _, Messages} when length(Messages) < 2*ChannelLimit, rpc:call(Slave, dps_channel, messages, [chan1, 0])),

  ok.



test_replication_works(#env{slaves = [{Slave,_,_}|_]}) ->
  assert_remote_start(),

  dps:new(chan1),

  RemoteChanel = rpc:call(Slave, dps_channel, find, [chan1]),
  ?assertEqual(0, dps:subscribe(RemoteChanel)),
  dps:publish(chan1, message1),

  receive
    Reply -> ?assertMatch({dps_msg, chan1, _, [message1]}, Reply)
  after
    1000 ->
      M = dps_channel:messages(RemoteChanel, 0),
      ?debugFmt("There: ~p", [M]),
      error(parent_timeout)
  end.


-endif.
