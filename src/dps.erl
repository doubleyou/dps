-module(dps).

-export([new/0,
         new/1,
         publish/2,
         subscribe/1,
         subscribe/2,
         multi_fetch/2,
         multi_fetch/3,
         start/0,
         start/1
         ]).


-type tag() :: term().
-type message() :: term().
-type timestamp() :: non_neg_integer().

-export_type([message/0, timestamp/0, tag/0]).

-spec start() -> ok.
start() ->
    application:start(dps).

-spec start([Master::atom()]) -> ok.
start([Master]) ->
    pong = net_adm:ping(Master),
    application:start(dps).


-spec new() -> Tag :: binary().
new() ->
    Tag = dps_uuid:gen(),
    new(Tag),
    Tag.

-spec new(Tag :: tag()) -> Tag :: tag().
new(Tag) ->
    dps_channels_manager:create(Tag),
    Tag.

-spec publish(Tag :: tag(), Msg :: message()) -> TS :: timestamp().
publish(Tag, Msg) ->
    dps_channel:publish(Tag, Msg).

-spec subscribe(Tag :: tag()) -> TotalMsgs :: non_neg_integer().
subscribe(Tag) ->
    dps_channel:subscribe(Tag).

-spec subscribe(Tag :: tag(), TS :: timestamp()) -> TotalMsgs :: non_neg_integer().
subscribe(Tag, TS) ->
    dps_channel:subscribe(Tag, TS).

-spec multi_fetch([Tag :: tag()], TS :: timestamp()) -> 
    {ok, LastTS :: timestamp(), [Msg :: term()]}.
multi_fetch(Tags, TS) ->
    dps_channel:multi_fetch(Tags, TS).

-spec multi_fetch([Tag :: tag()], TS :: timestamp(), Timeout :: non_neg_integer()) -> 
    {ok, LastTS :: timestamp(), [Msg :: message()]}.
multi_fetch(Tags, TS, Timeout) ->
    dps_channel:multi_fetch(Tags, TS, Timeout).





