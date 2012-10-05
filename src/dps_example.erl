-module(dps_example).

-export([start/0]).




-spec start() -> ok.
start() ->
    {ok, Nodes} = file:consult("priv/nodes.cfg"),
    {ok, Host} = inet:gethostname(),
    [net_adm:ping(list_to_atom(atom_to_list(Node) ++ "@" ++ Host)) || {Node, _} <- Nodes],
    application:start(dps).

