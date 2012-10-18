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

join([]) -> [];
join(Messages) -> join(Messages, true).

join([Message|Messages], true) -> [Message|join(Messages, false)];
join([Message|Messages], false)-> [",",Message|join(Messages, false)];
join([], _) -> [].

handle(Req, poll) ->
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
    {ok, Req4} = cowboy_req:reply(200, [], ["{\"seq\":", integer_to_list(Seq), ",\"messages\":[", join(Messages), "]}\n"], Req3),
    {ok, Req4, poll}
  catch
    throw:{error,Status} ->
      {ok, Req5} = cowboy_req:reply(400, json_headers(), <<"{\"error\" : \"",(atom_to_binary(Status,latin1))/binary,"\"}\n">>, Req),
      {ok, Req5, push}
  end;


handle(Req, push) ->
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


