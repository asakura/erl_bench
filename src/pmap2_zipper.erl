-module(pmap2_zipper).

-export([pmap/3, pmap/4, take/3, process/6]).

-define(CHUNK_LENGTH, 100).

-record(options,
        {max_process_count :: pos_integer(),
         chunk_length = ?CHUNK_LENGTH :: pos_integer(),
         parent_pid :: pid(),
         parent_ref :: reference(),
         fun_timeout = 100 :: pos_integer()}).

-type options() :: #options{}.
-type cps() ::
    {done, LastChunkNo :: pos_integer()} |
    {continue, Chunk :: list(), NextChunkNo :: pos_integer(), nonempty_list()}.
-type zipper() :: {Pre :: list(), Post :: list()}.
-type funfun() :: fun((term()) -> term()).
-type process_count() :: pos_integer().
-type input_list() :: [term()].

-spec pmap(funfun(), input_list(), process_count()) -> [term()].
pmap(Fn, List, ProcessCount) when ProcessCount > 1 ->
    pmap(Fn, List, ProcessCount, ?CHUNK_LENGTH).

pmap(Fn, List, ProcessCount, ChunkLength) when ProcessCount > 1 andalso ChunkLength > 0 ->
    ParentPid = self(),
    ParentRef = make_ref(),
    Opts =
        #options{max_process_count = ProcessCount,
                 parent_pid = ParentPid,
                 parent_ref = ParentRef,
                 chunk_length = ChunkLength},
    do_pmap(Fn, List, Opts).

-spec flush_inbox(Refs :: #{reference() => any()}) -> ok.
flush_inbox(Refs) ->
    receive
        {Ref, result, _, _} when is_map_key(Ref, Refs) ->
            flush_inbox(Refs);
        {'DOWN', Ref, process, _, _} when is_map_key(Ref, Refs) ->
            flush_inbox(Refs)
    after 0 ->
        ok
    end.

-spec insert(term(), zipper()) -> zipper().
insert(Val, {Pre, Post}) ->
    {Pre, [Val | Post]}.

-spec prev(zipper()) -> zipper().
prev({[H | T], Post}) ->
    {T, [H | Post]}.

-spec next(zipper()) -> zipper().
next({Pre, [H | T]}) ->
    {[H | Pre], T}.

-spec return(nonempty_list({pos_integer(), list()}), zipper()) -> nonempty_list().
return(Acc = {[{Last, _} | _], [{Current, _} | _]}, [{ChunkNo, Chunk}|Rest])
  when ChunkNo > Last andalso ChunkNo =< Current ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return(Acc = {[], [{Current, _} | _]}, [{ChunkNo, Chunk}|Rest]) when ChunkNo < Current ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return(Acc = {[{Last, _} | _], []}, [{ChunkNo, Chunk}|Rest]) when ChunkNo > Last ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return(Acc = {_, [{Current, _} | _]}, Chunks = [{ChunkNo, _Chunk}|_Rest]) when ChunkNo > Current ->
    return(next(Acc), Chunks);
return(Acc = {_, [{Current, _} | _]}, Chunks = [{ChunkNo, _Chunk}|_Rest]) when ChunkNo < Current ->
    return(prev(Acc), Chunks);
return(Acc = {[], []}, [{ChunkNo, Chunk}|Rest]) ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return({Pre, Post}, []) ->
    lists:foldl(fun({_, Value}, Acc) -> Value ++ Acc end, [], Pre)
        ++ lists:foldr(fun({_, Value}, Acc) -> Value ++ Acc end, [], Post).

-spec process(ParentPid :: pid(),
              ParentRef :: reference(),
              ChunkNo :: non_neg_integer(),
              Fn :: fun((any()) -> any()),
              Chunk :: nonempty_list(),
              Acc :: list()) -> ok | no_return().
process(ParentPid, ParentRef, ChunkNo, Fn, [Item | Rest], Acc) ->
    process(ParentPid, ParentRef, ChunkNo, Fn, Rest, [Fn(Item) | Acc]);
process(ParentPid, ParentRef, ChunkNo, _, [], Result) ->
    ParentPid ! {ParentRef, result, ChunkNo, Result},
    ok.

-spec do_pmap(fun((any()) -> any()), list(), Opts :: options()) -> {ok, list()} | error.
do_pmap(Fn, List, Opts) ->
    Continuation = take(List, Opts#options.chunk_length, 1),
    {Result, Refs} =
        catch do_pmap(Continuation,
                      Opts#options.max_process_count,
                      _Refs = #{},
                      _Acc = [],
                      Fn,
                      Opts),
    maps:foreach(fun(ChildRef, {ChildPid, TimerRef}) ->
                    erlang:cancel_timer(TimerRef),
                    true = demonitor(ChildRef),
                    true = exit(ChildPid, kill)
                 end,
                 Refs),
    try Result of
        error ->
            error;
        Chunks ->
            {ok, return({[], []}, Chunks)}
    after
        flush_inbox(maps:put(Opts#options.parent_ref, undefined, Refs))
    end.

-spec do_pmap(Continuation :: cps(),
              ProcessBudget :: non_neg_integer(),
              Refs :: map(),
              Acc :: list(),
              fun((any()) -> any()),
              Opts :: options()) ->
                 {{Acc :: list(), LastChunkNo :: pos_integer()}, Refs :: map()} | no_return().
do_pmap(Continuation, 0, Refs, Acc, Fn, Opts) ->
    Running = maps:size(Refs),
    {NewAcc, LeftRunning, NewRefs} =
        partial_gather(Acc, Refs, Running, Running, Opts#options.parent_ref, 0),
    do_pmap(Continuation, Running - LeftRunning, NewRefs, NewAcc, Fn, Opts);
do_pmap({continue, Chunk, ChunkNo, NextChunk}, ProcessBudget, Refs, Acc, Fn, Opts) ->
    {ChildPid, ChildRef} =
        spawn_monitor(pmap2_zipper,
                      process,
                      [Opts#options.parent_pid, Opts#options.parent_ref, ChunkNo, Fn, Chunk, []]),
    TimerRef = erlang:send_after(Opts#options.fun_timeout, ChildPid, kill),
    NewRefs = maps:put(ChildRef, {ChildPid, TimerRef}, Refs),
    do_pmap(erlang:apply(pmap2_zipper, take, NextChunk), ProcessBudget - 1, NewRefs, Acc, Fn, Opts);
do_pmap({done, _LastChunkNo}, _, Refs, Acc, _, Opts) ->
    Running = maps:size(Refs),
    {NewAcc, _, RefsLeft} =
        partial_gather(Acc, Refs, Running, Running, Opts#options.parent_ref, 0),
    {NewAcc, RefsLeft}.

-spec partial_gather(Acc :: list(),
                     Refs :: map(),
                     WereRunning :: non_neg_integer(),
                     LeftRunning :: non_neg_integer(),
                     ParentRef :: reference(),
                     Timeout :: non_neg_integer()) ->
                        {Acc :: list(), Left :: non_neg_integer(), Refs :: map()} | no_return().
partial_gather(Acc, Refs, _, 0, _, _) ->
    {Acc, maps:size(Refs), Refs};
partial_gather(Acc, Refs, WereRunning, LeftRunning, ParentRef, Timeout) ->
    receive
        {Ref, result, ChunkNo, Data} when Ref =:= ParentRef ->
            partial_gather([{ChunkNo, Data} | Acc],
                           Refs,
                           WereRunning,
                           LeftRunning,
                           ParentRef,
                           Timeout);
        {'DOWN', ChildRef, process, _, Reason} when is_map_key(ChildRef, Refs) ->
            {{_, TimerRef}, NewRefs} = maps:take(ChildRef, Refs),
            erlang:cancel_timer(TimerRef),
            case Reason of
                normal ->
                    partial_gather(Acc, NewRefs, WereRunning, LeftRunning - 1, ParentRef, Timeout);
                _ ->
                    throw({error, NewRefs})
            end
    after Timeout ->
        case WereRunning =:= LeftRunning of
            true ->
                NewTimeout = max(Timeout, 1) * 2,
                partial_gather(Acc, Refs, WereRunning, LeftRunning, ParentRef, NewTimeout);
            _ ->
                partial_gather(Acc, Refs, WereRunning, LeftRunning, ParentRef, 0)
        end
    end.

-spec take(list(), ToTake :: pos_integer(), NextChunkNo :: pos_integer()) -> cps().
take(List, ToTake, NextChunkNo) ->
    case do_take(List, ToTake, []) of
        {[], []} ->
            %% returns LastChunkNo
            {done, NextChunkNo - 1};
        {Chunk, Rest} ->
            {continue, Chunk, NextChunkNo, [Rest, ToTake, NextChunkNo + 1]}
    end.

-spec do_take(list(), non_neg_integer(), list()) -> {list(), list()}.
do_take(Rest, 0, Chunk) ->
    {Chunk, Rest};
do_take([H1, H2, H3, H4, H5, H6, H7, H8, H9, H10 | Rest], Left, Chunk) ->
    do_take(Rest, Left - 10, [H10, H9, H8, H7, H6, H5, H4, H3, H2, H1 | Chunk]);
do_take([H | Rest], Left, Chunk) ->
    do_take(Rest, Left - 1, [H | Chunk]);
do_take([], _, Chunk) ->
    {Chunk, []}.
