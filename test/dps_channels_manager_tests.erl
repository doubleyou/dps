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
    fun test_slaves_are_ready/0
  ]}.

-record(env, {
  manager,
  modules,
  slaves = []
}).

setup() ->
  Modules = [dps_channels_manager, dps_channels_sup],
  meck:new(Modules, [{passthrough,true}]),
  {ok, Manager} = gen_server:start_link({local, dps_channels_manager}, dps_channels_manager, [], []),
  unlink(Manager),
  meck:expect(dps_channels_sup, start_channel, fun(Tag) ->
    {ok,Pid} = dps_channel:start_link(Tag),
    unlink(Pid),
    {ok, Pid}
  end),

  net_kernel:start([dps_test, shortnames]),
  erlang:set_cookie(node(), mytestcookie),
  {ok,Host} = inet:gethostname(),
  {ok,Slave1} = slave:start_link(Host, dps_test1, "-setcookie mytestcookie"),
  {ok,Slave2} = slave:start_link(Host, dps_test2, "-setcookie mytestcookie"),
  {ok,Slave3} = slave:start_link(Host, dps_test3, "-setcookie mytestcookie"),

  #env{modules = Modules, manager = Manager, slaves = [Slave1, Slave2, Slave3]}.

teardown(#env{modules = Modules, manager = Manager, slaves = Slaves}) ->
  [slave:stop(Slave) || Slave <- Slaves],
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


test_slaves_are_ready() ->
  ?assertMatch(Nodes when length(Nodes) == 3, nodes()),
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


-endif.