-module(dps).

-export([start/0,
         new/0,
         new/1,
         publish/2,
         subscribe/1]).

start() ->
    {ok, Nodes} = file:consult("priv/nodes.cfg"),
    [net_adm:ping(Node) || Node <- Nodes],
    application:start(dps).

new() ->
    new(os:cmd("uuidgen") -- "\n").

new(Tag) ->
    dps_channels_manager:create(Tag).

publish(Tag, Msg) ->
    dps_channel:publish(Tag, Msg).

subscribe(Tag) ->
    dps_channel:subscribe(Tag).
