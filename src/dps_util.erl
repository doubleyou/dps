-module(dps_util).

-export([ts/0]).

ts() ->
    {Megasecs, Secs, Microsecs} = now(),
    Microsecs + 1000000 * (Secs + 1000000 * Megasecs).
