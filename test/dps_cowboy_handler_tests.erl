-module(dps_cowboy_handler_tests).
-compile(export_all).
-include_lib("eunit/include/eunit.hrl").


dps_session_test_() ->
  TestFunctions = [F || {F,1} <- ?MODULE:module_info(exports),
                            lists:prefix("test_", atom_to_list(F))],
  {foreach,
    fun setup/0,
    fun teardown/1,
    [{with, [fun ?MODULE:F/1]} || F <- TestFunctions]
  }.

-record(env, {
  url
}).

setup() ->
  gen_event:delete_handler(error_logger, error_logger_tty_h, []),
  application:start(dps),
  application:start(ranch),
  application:start(cowboy),
  inets:start(),

  Dispatch = [{'_', [
    {[<<"poll">>], dps_cowboy_handler, [poll]},
    {[<<"push">>], dps_cowboy_handler, [push]}
  ]}],

  cowboy:start_http(dps_test_listener, 1, [{port, 0},{max_connections,65536}],
    [{dispatch, Dispatch},{max_keepalive,4096}]
  ),
  Port = ranch:get_port(dps_test_listener),
  Url = lists:flatten(io_lib:format("http://localhost:~B/", [Port])),
  #env{url = Url}.


teardown(#env{}) ->
  application:stop(dps),
  application:stop(ranch),
  application:stop(cowboy),
  % cowboy:stop_listener(dps_test_listener),
  ok.

test_push(#env{url = Url}) ->
  Session = dps_session:find_or_create(<<"sess1">>, [<<"chan1">>]),
  ?assertMatch({ok, {{_,200,_},_,"true\n"}}, httpc:request(post, {Url ++ "push", [], "text/plain", "chan1|message1"}, [],[])),
  ?assertEqual({ok, 1, [<<"message1">>]}, dps_session:fetch(Session, 0)),
  ok.

test_poll_after_push(#env{url = Url}) ->
  Session = dps_session:find_or_create(<<"sess1">>, [<<"chan1">>]),
  ?assertMatch({ok, {{_,200,_},_,"true\n"}}, httpc:request(post, {Url ++ "push", [], "text/plain", "chan1|message1"}, [],[])),
  ?assertMatch({ok, {{_,200,_},_,"1|message1\n"}}, httpc:request(post, {Url ++ "poll?session=sess1&channels=chan1,main&seq=0", [], "text/plain", ""}, [],[])),
  ok.



