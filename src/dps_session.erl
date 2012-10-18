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
        find_or_create/2,
        limit/0,
         fetch/2]).

-record(state, {
    session,
    timer,
    seq = 0,
    channels = [],
    messages = [],
    waiters = []
}).

-define(TIMEOUT, 30000).

%%
%% External API
%%

-spec limit() -> Limit::non_neg_integer().
limit() -> 100.


find_or_create(SessionId, Channels) ->
    Session = case dps_sessions_manager:find(SessionId) of
        undefined ->
            [dps:new(Channel) || Channel <- Channels],
            Session_ = dps_sessions_manager:create(SessionId),
            dps_session:add_channels(Session_, Channels),
            Session_;
        Session_ ->
            Session_
    end,
    Session.




add_channels(Session, Channels) when is_pid(Session) ->
    gen_server:call(Session, {add_channels, Channels}).

-spec fetch(Session::pid(), OldSeq::non_neg_integer()) -> {ok, Seq::non_neg_integer(), [Message::term()]}.
fetch(Session, OldSeq) when is_pid(Session) ->
    try gen_server:call(Session, {fetch, OldSeq}, 30000)
    catch
        exit:{timeout,_} -> {ok, OldSeq, []}
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


handle_call({fetch, OldSeq}, _From, State = #state{messages = Messages, timer = OldTimer, seq = Seq}) 
    when OldSeq < Seq ->
    erlang:cancel_timer(OldTimer),
    Timer = erlang:send_after(?TIMEOUT, self(), timeout),
    NewMessages = leave_new(Seq - OldSeq, Messages),
    {reply, {ok, Seq, lists:reverse(NewMessages)}, State#state{messages = NewMessages, timer = Timer}};

handle_call({fetch, NewSeq}, From, State = #state{timer = OldTimer, seq = Seq, waiters = Waiters}) 
    when NewSeq >= Seq ->
    erlang:cancel_timer(OldTimer),
    Timer = erlang:send_after(?TIMEOUT, self(), timeout),
    {noreply, State#state{timer = Timer, waiters = [From|Waiters]}};

handle_call({add_channels, Channels}, _From, State = #state{
                                                    channels = OldChannels}) ->
    [dps:subscribe(Channel) || Channel <- Channels -- OldChannels],
    NewChannels = sets:to_list(sets:from_list(Channels ++ OldChannels)),
    {reply, NewChannels, State#state{channels = NewChannels}};
handle_call(Msg, _From, State) ->
    {reply, {error, {unknown_call, Msg}}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({dps_msg, _Tag, Message}, State = #state{waiters = Waiters, messages = Messages, seq = Seq}) ->
    [gen_server:reply(From, {ok, Seq+1, [Message]}) || From <- Waiters],
    Limit = limit(),
    NewMessages = case length(Messages) of
        Len when Len >= 2*Limit -> element(1,lists:split(Limit,[Message|Messages]));
        _ -> [Message|Messages]
    end,
    {noreply, State#state{seq = Seq + 1, messages = NewMessages}};
handle_info(timeout, #state{waiters = []} = State) ->
    {stop, normal, State};
handle_info(timeout, #state{timer = OldTimer} = State) ->
    erlang:cancel_timer(OldTimer),
    Timer = erlang:send_after(?TIMEOUT, self(), timeout),
    {noreply, State#state{timer = Timer}};
handle_info(_Info, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

leave_new(0, _) ->  [];
leave_new(_, []) -> [];
leave_new(Count, [Message|Messages]) -> [Message|leave_new(Count - 1, Messages)].
