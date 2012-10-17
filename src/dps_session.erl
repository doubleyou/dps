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
    channels = [],
    messages = []
}).

%%
%% External API
%%

add_channels(Session, Channels) ->
    gen_server:call(dps_sessions_manager:find(Session), {add_channels, Channels}).

fetch(Session) ->
    gen_server:call(dps_sessions_manager:find(Session), fetch).

start_link(Session) ->
    gen_server:start_link(?MODULE, Session, []).

%%
%% gen_server callbacks
%%

init(Session) ->
    {ok, #state{session = Session}}.

handle_call(fetch, _From, State = #state{messages = Messages}) ->
    {reply, Messages, State#state{messages = []}};
handle_call({add_channels, Channels}, _From, State = #state{
                                                    channels = OldChannels}) ->
    [dps:subscribe(Channel) || Channel <- Channels -- OldChannels],
    NewChannels = sets:to_list(sets:from_list(Channels ++ OldChannels)),
    {reply, NewChannels, State#state{channels = NewChannels}};
handle_call(Msg, _From, State) ->
    {reply, {error, {unknown_call, Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({dps_msg, _Tag, _LastTS, NewMessages}, State = #state{
                                                    messages = Messages}) ->
    {noreply, State#state{messages = NewMessages ++ Messages}};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.
