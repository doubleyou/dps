-module(dps_cowboy_handler).
-include_lib("eunit/include/eunit.hrl").


-export([init/3, handle/2, terminate/2]).
-export([websocket_init/3, websocket_handle/3,
    websocket_info/3, websocket_terminate/3]).



-define(TIMEOUT, 60000).

init({tcp, http}, Req, [poll]) ->
  {Upgrade, Req1} = cowboy_req:header(<<"upgrade">>, Req),
  case Upgrade of
    <<"WebSocket">> ->
      {upgrade, protocol, cowboy_websocket};
    undefined ->
      {ok, Req1, poll}
  end;

init({tcp,http},Req,[push]) ->
  {ok, Req, push}.


json_headers() ->
  [{<<"Content-Type">>, <<"application/json">>},{<<"Access-Control-Allow-Origin">>, <<"*">>},
  {<<"Access-Control-Allow-Methods">>, <<"POST, GET, OPTIONS">>},
  {<<"Access-Control-Allow-Headers">>, <<"Content-Type, Origin, Accept">>}].

join([]) -> [];
join(Messages) -> join(Messages, true).

join([Message|Messages], true) -> [Message|join(Messages, false)];
join([Message|Messages], false)-> [",",Message|join(Messages, false)];
join([], _) -> [].

handle(Req, poll) ->
  {<<"POST">>, _} = cowboy_req:method(Req),
  try
    {RawChannels, Req2} = cowboy_req:qs_val(<<"channels">>, Req),
    is_binary(RawChannels) orelse throw({error,no_channels}),
    Channels = binary:split(RawChannels, <<",">>, [global]),

    {SessionId, Req3} = cowboy_req:qs_val(<<"session">>, Req2),
    is_binary(RawChannels) orelse throw({error,no_session}),

    {OldSeq_, Req4} = cowboy_req:qs_val(<<"seq">>, Req3, <<"0">>),
    OldSeq = cowboy_http:digits(OldSeq_),

    Session = dps_session:find_or_create(SessionId, Channels),
    {ok, Seq, Messages} = dps_session:fetch(Session, OldSeq),
    {ok, Req5} = cowboy_req:reply(200, [], ["{\"seq\":", integer_to_list(Seq), ",\"messages\":[", join(Messages), "]}\n"], Req4),
    {ok, Req5, poll}
  catch
    throw:{error,Status} ->
      {ok, Req6} = cowboy_req:reply(400, json_headers(), <<"{\"error\" : \"",(atom_to_binary(Status,latin1))/binary,"\"}\n">>, Req),
      {ok, Req6, push}
  end;


handle(Req, push) ->
  {Method, Req1} = cowboy_req:method(Req),
  case Method of
    <<"POST">> ->
      handle_push(Req1);
    <<"OPTIONS">> ->
      handle_push_options(Req1)
  end.

handle_push(Req) ->
  {ok, Msg, Req1} = cowboy_req:body(Req),
  try  
    jiffy:decode(Msg),
    {Channel, Req2} = cowboy_req:qs_val(<<"channel">>, Req1),
    is_binary(Channel) orelse throw({error,no_channel}),
    dps:new(Channel),
    dps:publish(Channel, Msg),
    {ok, Req3} = cowboy_req:reply(200, json_headers(), <<"true\n">>, Req2),
    {ok, Req3, push}
  catch
    throw:{error,{_,invalid_json}} ->
      {ok, Req5} = cowboy_req:reply(400, json_headers(), <<"{\"error\" : \"invalid_json\"}\n">>, Req1),
      {ok, Req5, push};
    throw:{error,no_channel} ->
      {ok, Req5} = cowboy_req:reply(400, json_headers(), <<"{\"error\" : \"no_channel\"}\n">>, Req1),
      {ok, Req5, push}
  end.

handle_push_options(Req) ->
  {ok, Req1} = cowboy_req:reply(200, json_headers(), "ok\n", Req),
  {ok, Req1, push}.

terminate(_Req, _State) ->
  ok.



%%%% Websocket


websocket_init(_TransportName, Req, _Opts) ->
    {RawChannels, Req2} = cowboy_req:qs_val(<<"channels">>, Req),
    is_binary(RawChannels) orelse throw({error,no_channels}),
    Channels = binary:split(RawChannels, <<",">>, [global]),

    {OldSeq_, Req3} = cowboy_req:qs_val(<<"seq">>, Req2, <<"0">>),
    OldSeq = cowboy_http:digits(OldSeq_),

    [dps:subscribe(Channel, OldSeq) || Channel <- Channels],
    {ok, Req3, undefined_state}.

websocket_handle({text, Msg}, Req, State) ->
    {reply, {text, << "That's what she said! ", Msg/binary >>}, Req, State};
websocket_handle(_Data, Req, State) ->
    {ok, Req, State}.

websocket_info({timeout, _Ref, Msg}, Req, State) ->
    erlang:start_timer(1000, self(), <<"How' you doin'?">>),
    {reply, {text, Msg}, Req, State};
websocket_info({dps_msg, _Tag, _LastTS, Messages}, Req, State) ->
    {reply, {text, ["{\"messages\":[", join(Messages), "]}\n"]}, Req, State};
websocket_info(_Info, Req, State) ->
    io:format("Info: ~p~n", [_Info]),
    {ok, Req, State}.

websocket_terminate(_Reason, _Req, _State) ->
    ok.


