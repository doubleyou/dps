-module(dps_session).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-export([add_channels/2,
         fetch/1]).

-record(state, {
    session,
    timer,
    channels = [],
    messages = [],
    waiters = []
}).

-define(TIMEOUT, 30000).

%%
%% External API
%%

add_channels(Session, Channels) when is_pid(Session) ->
    gen_server:call(Session, {add_channels, Channels}).

fetch(Session) when is_pid(Session) ->
    try gen_server:call(Session, fetch, 30000)
    catch
        exit:{timeout,_} -> []
    end.

start_link(Session) ->
    gen_server:start_link(?MODULE, Session, []).

%%
%% gen_server callbacks
%%

init(Session) ->
    Timer = erlang:send_after(?TIMEOUT, self(), timeout),
    {ok, #state{session = Session, timer = Timer}}.

handle_call(fetch, From, State = #state{messages = [], timer = OldTimer, waiters = Waiters}) ->
    erlang:cancel_timer(OldTimer),
    Timer = erlang:send_after(?TIMEOUT, self(), timeout),
    {noreply, State#state{waiters = [From|Waiters], timer = Timer}};


handle_call(fetch, _From, State = #state{messages = Messages, timer = OldTimer}) ->
    erlang:cancel_timer(OldTimer),
    Timer = erlang:send_after(?TIMEOUT, self(), timeout),
    {reply, Messages, State#state{messages = [], timer = Timer}};

handle_call({add_channels, Channels}, _From, State = #state{
                                                    channels = OldChannels}) ->
    [dps:subscribe(Channel) || Channel <- Channels -- OldChannels],
    NewChannels = sets:to_list(sets:from_list(Channels ++ OldChannels)),
    {reply, NewChannels, State#state{channels = NewChannels}};
handle_call(Msg, _From, State) ->
    {reply, {error, {unknown_call, Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({dps_msg, _Tag, _LastTS, NewMessages}, State = #state{waiters = [],
                                                    messages = Messages}) ->
    {noreply, State#state{messages = NewMessages ++ Messages}};
handle_info({dps_msg, _Tag, _LastTS, NewMessages}, State = #state{waiters = Waiters, messages = []}) ->
    [gen_server:reply(From, Msg) || From <- Waiters, Msg <- NewMessages],
    {noreply, State};
handle_info(timeout, State) ->
    {stop, normal, State};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
