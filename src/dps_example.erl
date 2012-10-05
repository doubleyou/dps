-module(dps_example).

-export([start/0]).




-spec start() -> ok.
start() ->
    {ok, Nodes} = file:consult("priv/nodes.cfg"),
    {ok, Host} = inet:gethostname(),
    [net_adm:ping(list_to_atom(atom_to_list(Node) ++ "@" ++ Host)) || {Node, _} <- Nodes],
    application:start(dps),

    OurNode = list_to_atom(hd(string:tokens(atom_to_list(node()), "@"))),

    {OurNode, Port} = lists:keyfind(OurNode, 1, Nodes),

    dps:new(example_channel1),
    dps:new(example_channel2),

    application:start(ranch),
    application:start(cowboy),
    application:start(mimetypes),

    Dispatch = [
        %% {URIHost, list({URIPath, Handler, Opts})}
        {'_', [
          {[<<"poll">>], dps_cowboy_handler, [poll]},
          {[<<"push">>], dps_cowboy_handler, [push]},
          {[], cowboy_static, [
            {directory, <<"wwwroot">>},
            {mimetypes, [{<<".html">>,[<<"text/html">>]}]},
            {file, <<"index.html">>}
          ]},
          {['...'], cowboy_static, [
            {directory,<<"wwwroot">>},
            {mimetypes, {fun mimetypes:path_to_mimes/2, default}}
          ]}
        ]}
    ],


    cowboy:start_http(dps_http_listener, 100, [{port, Port}],
      [{dispatch, Dispatch}]
    ).



