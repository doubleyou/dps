-module(dps_cowboy_handler).
-include_lib("eunit/include/eunit.hrl").


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
  {RawChannels, Req2} = cowboy_req:qs_val(<<"channels">>, Req),
  Channels = binary:split(RawChannels, <<",">>, [global]),

  {SessionId, Req3} = cowboy_req:qs_val(<<"session">>, Req2),
  Session = dps_session:find_or_create(SessionId, Channels),
  Messages = dps_session:fetch(Session),
  {ok, Req4} = cowboy_req:reply(200, [], Messages, Req3),
  {ok, Req4, poll};


handle(Req, push) ->
  {ok, Msg, Req1} = cowboy_req:body(Req),
  try jiffy:decode(Msg) of
    _ ->
      {Channel, Req2} = cowboy_req:qs_val(<<"channel">>, Req1),
      is_binary(Channel) orelse throw({error,no_channel}),
      dps:new(Channel),
      dps:publish(Channel, Msg),
      {ok, Req3} = cowboy_req:reply(200, json_headers(), <<"true\n">>, Req2),
      {ok, Req3, push}
  catch
    throw:{error,{_,invalid_json}} ->
      {ok, Req3} = cowboy_req:reply(400, json_headers(), <<"{\"error\" : \"invalid_json\"}\n">>, Req1),
      {ok, Req3, push};
    throw:{error,no_channel} ->
      {ok, Req3} = cowboy_req:reply(400, json_headers(), <<"{\"error\" : \"no_channel\"}\n">>, Req1),
      {ok, Req3, push}
  end.


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


