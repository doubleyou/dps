-module(dps).

-export([start/0,
         new/0,
         new/1,
         publish/2,
         subscribe/1]).

-spec start() -> ok.
start() ->
    {ok, Nodes} = file:consult("priv/nodes.cfg"),
    [net_adm:ping(Node) || Node <- Nodes],
    application:start(dps).

-spec new() -> Tag :: string().
new() ->
    Tag = os:cmd("uuidgen") -- "\n",
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
