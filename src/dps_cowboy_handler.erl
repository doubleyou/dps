-module(dps_cowboy_handler).


-export([init/3, handle/2, terminate/2]).
-export([websocket_init/3, websocket_handle/3,
    websocket_info/3, websocket_terminate/3]).



-define(TIMEOUT, 60000).

init({tcp, http}, Req, [poll]) ->
  {Upgrade, Req1} = cowboy_req:header(<<"upgrade">>, Req),
  case Upgrade of
    <<"websocket">> ->
      {upgrade, protocol, cowboy_websocket};
    undefined ->
      {ok, Req1, poll}
  end;

init({tcp,http},Req,[push]) ->
  {ok, Req, push}.


json_headers() ->
  [{<<"Content-Type">>, <<"application/json">>},{<<"Access-Control-Allow-Origin">>, <<"*">>},
  {<<"Access-Control-Allow-Methods">>, <<"POST, GET, OPTIONS">>},
  {<<"Access-Control-Allow-Headers">>, <<"Content-Type">>}].

handle(Req, poll) ->
  {TS, Req2} = cowboy_req:qs_val(<<"ts">>, Req),
  {RawChannels, _} = cowboy_req:qs_val(<<"channels">>, Req),
  Channels = [list_to_binary(L) || L <- string:tokens(binary_to_list(RawChannels), ",")],
  LastTS = case TS of
    undefined -> 0;
    _ -> list_to_integer(binary_to_list(TS))
  end,
  [dps:new(Channel) || Channel <- Channels],
  {ok, LastTS, Messages} = dps:multi_fetch(Channels, LastTS, 1000),
%%  JSON = mochijson2:encode({struct, [{ts, LastTS}, {messages, Messages}]}),
%%  {ok, Req3} = cowboy_req:reply(200, json_headers(), JSON, Req2),
  Reply = [integer_to_list(LastTS), ",", Messages],
  {ok, Req3} = cowboy_req:reply(200, [], Reply, Req2),
  {ok, Req3, poll};


handle(Req, push) ->
  {ok, Message, Req1} = cowboy_req:body(Req),
  [Channel, Msg] = split_post(Message, <<>>),
  dps:new(Channel),
  TS = dps:publish(Channel, Msg),
  JSON = mochijson2:encode({struct, [{ts, TS}]}),
  {ok, Req2} = cowboy_req:reply(200, json_headers(), JSON, Req1),
  {ok, Req2, push}.

terminate(_Req, _State) ->
  ok.

split_post(<<"|",Rest/binary>>, Acc) ->
    [Acc, Rest];
split_post(<<C:8,Rest/binary>>, Acc) ->
    split_post(<<Acc/binary,C:8>>, Rest).



%%%% Websocket


websocket_init(_TransportName, Req, _Opts) ->
    erlang:start_timer(1000, self(), <<"Hello!">>),
    {ok, Req, undefined_state}.

websocket_handle({text, Msg}, Req, State) ->
    {reply, {text, << "That's what she said! ", Msg/binary >>}, Req, State};
websocket_handle(_Data, Req, State) ->
    {ok, Req, State}.

websocket_info({timeout, _Ref, Msg}, Req, State) ->
    erlang:start_timer(1000, self(), <<"How' you doin'?">>),
    {reply, {text, Msg}, Req, State};
websocket_info(_Info, Req, State) ->
    {ok, Req, State}.

websocket_terminate(_Reason, _Req, _State) ->
    ok.


