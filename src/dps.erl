-module(dps).

-export([start/0,
         new/0,
         new/1,
         publish/2,
         subscribe/1,
         multi_fetch/2,
         multi_fetch/3
         ]).

-spec start() -> ok.
start() ->
    {ok, Nodes} = file:consult("priv/nodes.cfg"),
    [net_adm:ping(Node) || Node <- Nodes],
    application:start(dps).

-spec new() -> Tag :: string().
new() ->
    Tag = dps_uuid:gen(),
    new(Tag),
    Tag.

-spec new(Tag :: term()) -> Tag :: term().
new(Tag) ->
    dps_channels_manager:create(Tag),
    Tag.

-spec publish(Tag :: term(), Msg :: term()) -> TS :: non_neg_integer().
publish(Tag, Msg) ->
    dps_channel:publish(Tag, Msg).

-spec subscribe(Tag :: term()) -> TotalMsgs :: non_neg_integer().
subscribe(Tag) ->
    dps_channel:subscribe(Tag).


-spec multi_fetch([Tag :: term()], TS :: non_neg_integer()) -> 
    {ok, LastTS :: non_neg_integer(), [Msg :: term()]}.
multi_fetch(Tags, TS) ->
    dps_channel:multi_fetch(Tags, TS).

-spec multi_fetch([Tag :: term()], TS :: non_neg_integer(), Timeout :: non_neg_integer()) -> 
    {ok, LastTS :: non_neg_integer(), [Msg :: term()]}.
multi_fetch(Tags, TS, Timeout) ->
    dps_channel:multi_fetch(Tags, TS, Timeout).