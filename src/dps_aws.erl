-module(dps_aws).

-export([start/0]).

start() ->
    {ok, Nodes} = file:consult("priv/aws.cfg"),
    lists:map(fun net_adm:ping/1, Nodes),
    dps_example:start_everything().
