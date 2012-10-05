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
  end.

handle(Req, poll) ->
  {TS, Req2} = cowboy_req:qs_val(<<"ts">>, Req),
  LastTS = case TS of
    undefined -> 0;
    _ -> list_to_integer(binary_to_list(TS))
  end,
  {ok, LastTS1, Messages} = dps:multi_fetch([example_channel1, example_channel2], LastTS, 10000),
  JSON = [io_lib:format("{\"ts\":~B, \"messages\" : [", [LastTS1]), "]}"],
  {ok, Req3} = cowboy_req:reply(200, [{<<"Content-Type">>, <<"application/json">>}], JSON, Req2),
  {ok, Req3, poll}.

terminate(_Req, _State) ->
  ok.



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


