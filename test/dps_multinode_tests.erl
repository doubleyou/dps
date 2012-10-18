-module(dps_multinode_tests).
-compile(export_all).

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
  assert_create(),
  ok.


test_slaves_are_ready() ->
  ?assertEqual(length(nodes()), ?NODE_COUNT),
  ok.



test_remote_channels_start() ->
  assert_remote_start(),

  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  assert_create(),

  {Replies2, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  RemoteChannels = [Pid || {_,Pid,_} <- Replies2, is_pid(Pid)],
  ?assertEqual([], BadNodes2),
  ?assertEqual(?NODE_COUNT, length(RemoteChannels)),
  ok.



test_remote_slaves_take_our_channels_on_start() ->
  assert_create(),
  assert_remote_start(),

  {Replies, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  RemoteChannels = [Pid || {_,Pid,_} <- Replies, is_pid(Pid)],
  ?assertEqual([], BadNodes2),
  ?assertEqual(?NODE_COUNT, length(RemoteChannels)),
  ok.




test_replication_works(#env{slaves = [{Slave,_,_}|_]}) ->
  assert_remote_start(),

  dps:new(chan1),

  RemoteChannel = rpc:call(Slave, dps_channel, find, [chan1]),
  ?assertMatch(_ when is_pid(RemoteChannel), RemoteChannel),
  dps:subscribe(RemoteChannel),
  dps:publish(chan1, message1),

  receive
    {dps_msg, chan1, message1} -> ok;
    Else -> error({strange,Else})
  after
    500 ->
      error(havent_received_replication_message)
  end.





assert_create() ->
  ?assertMatch({test_channel, Pid, Repl} when is_pid(Pid) andalso is_pid(Repl), dps_channels_manager:create(test_channel)).

assert_remote_start() ->
  {ok, [AppDesc]} = file:consult("../ebin/dps.app"),
  rpc:multicall(nodes(), application, load, [AppDesc]),
  ?assertMatch({_,[]}, rpc:multicall(nodes(), application, start, [dps])).



test2_replication_publish_when_node_is_not_initialized() ->
  assert_create(),
  [?assertMatch(TS when is_number(TS), dps_channel:publish(test_channel, N)) || N <- lists:seq(1,100)],
  ok.  



