-module(dps_channels_manager_tests).
-compile(export_all).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


manager_test_() ->
  {foreach,
  fun setup/0,
  fun teardown/1,
  [
    fun test_create/0,
    fun test_channel_failing/0,
    fun test_slaves_are_ready/0,
    fun test_remote_channels_start/0
  ]}.

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
    Slave
  end, lists:seq(1,?NODE_COUNT)),

  application:start(dps),
  {ok, [AppDesc]} = file:consult("../ebin/dps.app"),
  rpc:multicall(application, load, [AppDesc]),
  #env{modules = Modules, slaves = Slaves}.

teardown(#env{modules = Modules, slaves = Slaves}) ->
  [slave:stop(Slave) || Slave <- Slaves],
  meck:unload(Modules),
  application:stop(dps),
  ok.


test_create() ->
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:create(test_channel)),
  ok.


test_slaves_are_ready() ->
  ?assertMatch(Nodes when length(Nodes) == ?NODE_COUNT, nodes()),
  ok.


test_channel_failing() ->
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:create(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:find(test_channel)),
  {ok, Pid} = dps_channels_manager:find(test_channel),
  ?assertNotEqual(Pid, whereis(dps_channels_manager)),
  erlang:exit(Pid, kill),
  timer:sleep(50),
  gen_server:call(dps_channels_manager, sync_call), % Just for synchronisation
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ok.



test_remote_channels_start() ->
  {Replies, BadNodes} = rpc:multicall(nodes(), application, start, [dps]),
  ?assertMatch(PidList when length(PidList) == ?NODE_COUNT, Replies),
  ?assertEqual([], BadNodes),
  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  ?assertMatch({ok, Pid} when is_pid(Pid), dps_channels_manager:create(test_channel)),

  {RemoteChannels, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  ?assertEqual([], BadNodes2),
  Pids = [Pid || {ok, Pid} <- RemoteChannels],
  ?assertMatch(Pids_ when length(Pids_) == ?NODE_COUNT, Pids),
  ok.












-endif.