-module(dps_benchmark).
-compile(export_all).


-define(COUNT, 32).
-define(NODE_COUNT, 3).

run1() ->
  application:start(dps),
  rpc:call(bench1@localhost, erlang, halt, []),
  rpc:call(bench2@localhost, erlang, halt, []),
  os:cmd("erl -pa ebin -smp enable -sname bench1@localhost -setcookie cookie -detached"),
  os:cmd("erl -pa ebin -smp enable -sname bench2@localhost -setcookie cookie -detached"),
  ping(bench1@localhost),
  ping(bench2@localhost),
  {_, BadNodes} = rpc:multicall(nodes(), dps, start, []),
  BadNodes == [] orelse error({nodes_failed,BadNodes}),
  run1(3).

ping(Node) -> ping(Node, 10).

ping(Node, 0) -> io:format("Failed to ping node ~p~n", [Node]), {error, failed};
ping(Node, Count) ->
  case net_adm:ping(Node) of
    pong -> ok;
    _ -> timer:sleep(200), ping(Node, Count - 1)
  end.



run1(ChannelCount) ->

  SendCollector = spawn(fun() ->
    timer:send_interval(1000, dump),
    timer:send_interval(10000, flush),
    put(now, erlang:now()),
    receive
      {senders, Senders} -> send_collector(0, Senders)
    after
      5000 -> error(failed_to_start_collector)
    end
  end),
  erlang:register(send_collector, SendCollector),
  Senders = [proc_lib:start_link(?MODULE, start_sender, [{channel, I}]) || I <- lists:seq(1,ChannelCount)],
  send_collector ! {senders, Senders},

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


send_collector(Total, Senders) ->
  receive
    {messages, _Channel, Count} -> send_collector(Total + Count, Senders);
    flush ->
      put(now, erlang:now()),
      send_collector(0, Senders);
    dump ->
      Delta = timer:now_diff(erlang:now(), get(now)) div 1000000,
      AliveSenders = [Pid || Pid <- Senders, erlang:is_process_alive(Pid)],
      case length(Senders) - length(AliveSenders) of
        0 -> ok;
        Dead -> io:format("dead senders: ~p~n", [Dead])
      end,
      if Delta > 0 ->
        io:format("Send: ~B msg/s~n", [Total div Delta]);
      true -> ok end,
      send_collector(Total, Senders)
  end.


start_sender(Chan) ->
  timer:send_interval(1000, dump),
  dps:new(Chan),
  put(msg_number, 1),
  proc_lib:init_ack(self()),
  JSON = iolist_to_binary(mochijson2:encode([lists:seq(1,512)])),
  run1_sender(Chan, 1, 1, JSON).

run1_sender(Chan, Number, Count, JSON) ->
  Count1 = receive
    dump -> send_collector ! {messages, Chan, Count}, 0
  after 0 -> Count + 1 end,
  TS = dps:publish(Chan, {Chan, Number, JSON}),
  is_number(TS) orelse error({failed_publish,Chan,Number}),
  put(msg_number,Number+1),
  run1_sender(Chan, Number + 1, Count1, JSON).



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
