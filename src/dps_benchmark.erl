-module(dps_benchmark).
-compile(export_all).


-define(COUNT, 32).

run1() ->
  application:start(dps),

  dps:new(channel),
  spawn(fun() ->
    timer:send_interval(1000, dump),
    put(now, erlang:now()),
    run1_sender(channel, 1)
  end),

  spawn(fun() ->
    run1_receiver([channel], 0)
  end),
  % Receivers = [spawn(fun() ->
  %   Chan = I div 4,
  %   Channels = [Chan, (Chan+1) rem ?COUNT, (Chan+2) rem ?COUNT, (Chan + 3) rem ?COUNT],
  %   run1_receiver(Channels, 1, 0)
  % end) || I <- lists:seq(0,?COUNT*4 - 1)],
  ok.


run1_receiver(Channels, TS) ->
  {ok, LastTS, Messages} = dps:multi_fetch(Channels, TS),
  if
    length(Messages) > 10 -> io:format("Messages: ~p~n", [length(Messages)]);
  true -> ok end,
  run1_receiver(Channels, LastTS).

run1_sender(Chan, Number) ->
  receive
    dump ->
      Delta = timer:now_diff(erlang:now(), get(now)) div 1000000,
      if Delta > 0 ->
        io:format("Send: ~B msg/s~n", [Number div Delta]);
      true -> ok end
  after 0 -> ok end,
  dps:publish(Chan, Number),
  run1_sender(Chan, Number + 1).


% run1_receiver(Channels, Number, TS) ->
%   {ok, LastTS, Messages} = dps:multi_fetch(Channels, TS),
%   run1_receiver(Channels, Number + length(Messages), LastTS).
