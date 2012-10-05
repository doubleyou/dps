-module(dps_channels_manager_tests).
-compile(export_all).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


manager_test_() ->
  TestFunctions = [F || {F,0} <- ?MODULE:module_info(exports),
                            lists:prefix("test_", atom_to_list(F))],
  {foreach,
    fun setup/0,
    fun teardown/1,
    [{atom_to_list(F), fun ?MODULE:F/0} || F <- TestFunctions]
  }.

-record(env, {
  modules,
  slaves = []
}).

-define(NODE_COUNT, 4).

setup() ->
  % Modules = [dps_channels_manager, dps_channels_sup],
  % meck:new(Modules, [{passthrough,true}]),
  process_flag(trap_exit, true),
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
  gen_event:delete_handler(error_logger, error_logger_tty_h, []),
  #env{modules = Modules, slaves = Slaves}.

teardown(#env{modules = Modules, slaves = Slaves}) ->
  [slave:stop(Slave) || Slave <- Slaves],
  meck:unload(Modules),
  application:stop(dps),
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



test_remote_channels_start() ->
  {Replies, BadNodes} = rpc:multicall(nodes(), application, start, [dps]),
  ?assertEqual(length(Replies), ?NODE_COUNT),
  ?assertEqual([], BadNodes),

  ?assertEqual(undefined, dps_channels_manager:find(test_channel)),
  assert_create(),

  {RemoteChannels, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  ?assertEqual([], BadNodes2),
  ?assertEqual(?NODE_COUNT, length(RemoteChannels)),
  ok.


test_remote_slaves_take_our_channels() ->
  assert_create(),
  ?assertMatch({_,[]}, rpc:multicall(nodes(), application, start, [dps])),

  {RemoteChannels, BadNodes2} = rpc:multicall(nodes(), dps_channels_manager, find, [test_channel]),
  ?assertEqual([], BadNodes2),
  ?assertEqual(?NODE_COUNT, length(RemoteChannels)),
  ok.



test_remote_channels_take_our_history_on_start() ->
  assert_create(),
  [dps_channel:publish(test_channel, N) || N <- lists:seq(1,100)],
%%  ?assertMatch({ok, TS, Messages} when is_number(TS) andalso length(Messages) == 100, dps_channel:messages(test_channel)),
%%  ?assertMatch({_,[]}, rpc:multicall(nodes(), application, start, [dps])),
%%
%%  {Replies, BadNodes2} = rpc:multicall(nodes(), dps_channel, messages, [undefined]),
%%  ?assertEqual([], BadNodes2),
%%  [Reply|_] = Replies,
%%
%%  ?assertMatch({ok, TS, Messages} when is_number(TS) andalso length(Messages) == 100, Reply),
  ok.

assert_create() ->
  ?assertMatch(Pid when is_pid(Pid), dps_channels_manager:create(test_channel)).




-endif.
