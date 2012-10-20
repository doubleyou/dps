-module(dps_session_tests).

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
  sess
}).

setup() ->
  gen_event:delete_handler(error_logger, error_logger_tty_h, []),
  % application:start(dps),
  {ok, Session} = dps_session:start_link(test_session),
  unlink(Session),
  #env{sess = Session}.


teardown(#env{sess = Session}) ->
  erlang:monitor(process, Session),
  Session ! timeout,
  receive
    {'DOWN', _, _, Session, _} -> ok
  after
    100 -> erlang:exit(Session, kill)
  end,
  % application:stop(dps),
  ok.


send(Session, Messages) ->
  [Session ! {dps_msg, test_channel, 1, [Msg]} || Msg <- Messages].

test_session_simple_fast_fetch(#env{sess = Session}) ->
  send(Session, [message1]),
  ?assertEqual({ok, 1, [message1]}, dps_session:fetch(Session, 0)).

test_session_proper_order(#env{sess = Session}) ->
  send(Session, [message1, message2, message3]),
  ?assertEqual({ok, 3, [message1, message2, message3]}, dps_session:fetch(Session, 0)).

test_session_fetch_only_new_messages(#env{sess = Session}) ->
  send(Session, [message1, message2, message3]),
  ?assertEqual({ok, 3, [message2, message3]}, dps_session:fetch(Session, 1)).


test_session_flush_old_messages(#env{sess = Session}) ->
  send(Session, [message1, message2, message3, message4]),
  ?assertEqual({ok, 4, [message2, message3, message4]}, dps_session:fetch(Session, 1)),
  ?assertEqual({ok, 4, [message2, message3, message4]}, dps_session:fetch(Session, 0)),
  send(Session, [message5, message6]),
  ?assertEqual({ok, 6, [message4, message5, message6]}, dps_session:fetch(Session, 3)),
  ok.



test_clean_messages(#env{sess = Session}) ->
  Limit = dps_session:limit(),
  Count = 4*Limit,
  send(Session, lists:seq(1,Count)),
  {ok, Seq, Messages} = dps_session:fetch(Session, 0),
  ?assertEqual(Count, Seq),
  ?assertMatch(Len when Len =< 2*Limit, length(Messages)),
  ok.



test_blocking_api(#env{sess = Session}) ->
  Ref = make_ref(),
  Session ! {'$gen_call', {self(), Ref}, {fetch, 0}},
  send(Session, [message1]),
  receive
    {Ref, Reply} -> ?assertMatch({ok, 1, [message1]}, Reply)
  after 100 -> exit(block_timeout)
  end.





