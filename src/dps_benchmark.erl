-module(dps_benchmark).
-compile(export_all).


-define(COUNT, 32).

run1() ->
  run1(3).

run1(ChannelCount) ->
  application:start(dps),

  SendCollector = spawn(fun() ->
    timer:send_interval(1000, dump),
    put(now, erlang:now()),
    send_collector(0)
  end),
  erlang:register(send_collector, SendCollector),
  [proc_lib:start_link(?MODULE, start_sender, [{channel, I}]) || I <- lists:seq(1,ChannelCount)],

  spawn(fun() ->
    Channels = [{channel,I} || I <- lists:seq(1,ChannelCount)],
    run1_receiver(Channels, 0, dict:new())
  end),
  % Receivers = [spawn(fun() ->
  %   Chan = I div 4,
  %   Channels = [Chan, (Chan+1) rem ?COUNT, (Chan+2) rem ?COUNT, (Chan + 3) rem ?COUNT],
  %   run1_receiver(Channels, 1, 0)
  % end) || I <- lists:seq(0,?COUNT*4 - 1)],
  ok.


send_collector(Total) ->
  receive
    {messages, _Channel, Count} -> send_collector(Total + Count);
    dump ->
      Delta = timer:now_diff(erlang:now(), get(now)) div 1000000,
      if Delta > 0 ->
        io:format("Send: ~B msg/s~n", [Total div Delta]);
      true -> ok end,
      send_collector(Total)
  end.


start_sender(Chan) ->
  timer:send_interval(1000, dump),
  dps:new(Chan),
  proc_lib:init_ack(self()),
  run1_sender(Chan, 1, 1).

run1_sender(Chan, Number, Count) ->
  Count1 = receive
    dump -> send_collector ! {messages, Chan, Count}, 0
  after 0 -> Count + 1 end,
  dps:publish(Chan, {Chan, Number}),
  run1_sender(Chan, Number + 1, Count1).



run1_receiver(Channels, TS, Stats) ->
  {ok, LastTS, Messages} = dps:multi_fetch(Channels, TS),
  {Stats1, Dropped} = collect_receive_stats(Stats, Messages),
  % if
  %   length(Messages) > 10 -> io:format("Messages: ~p~n", [length(Messages)]);
  % true -> ok end,
  if Dropped > 0 -> io:format("Receiver dropped ~p msg~n", [Dropped]);
    true -> ok end,
  run1_receiver(Channels, LastTS, Stats1).

collect_receive_stats(Stats, Messages) ->
  {Stats, 0}.


% run1_receiver(Channels, Number, TS) ->
%   {ok, LastTS, Messages} = dps:multi_fetch(Channels, TS),
%   run1_receiver(Channels, Number + length(Messages), LastTS).
