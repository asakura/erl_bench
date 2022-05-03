-module(pmap2_zipper_pool).

-export([pmap/3, pmap/4, take/3, process/4]).

-define(CHUNK_LENGTH, 100).

-record(options,
        {max_process_count :: pos_integer(),
         chunk_length = ?CHUNK_LENGTH :: pos_integer(),
         parent_pid :: pid(),
         parent_ref :: reference(),
         fun_timeout = 100 :: pos_integer()}).

-type options() :: #options{}.
-type cps() ::
    done | {continue, Chunk :: list(), NextChunkNo :: pos_integer(), nonempty_list()}.
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

-spec insert(term(), zipper()) -> zipper().
insert(Val, {Pre, Post}) ->
    {Pre, [Val | Post]}.

-spec prev(zipper()) -> zipper().
prev({[H | T], Post}) ->
    {T, [H | Post]}.

-spec next(zipper()) -> zipper().
next({Pre, [H | T]}) ->
    {[H | Pre], T}.

-spec return([{pos_integer(), list()}, ...], zipper()) -> nonempty_list().
return(Acc = {[{Last, _} | _], [{Current, _} | _]}, [{ChunkNo, Chunk} | Rest])
    when ChunkNo > Last andalso ChunkNo =< Current ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return(Acc = {[], [{Current, _} | _]}, [{ChunkNo, Chunk} | Rest])
    when ChunkNo < Current ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return(Acc = {[{Last, _} | _], []}, [{ChunkNo, Chunk} | Rest]) when ChunkNo > Last ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return(Acc = {_, [{Current, _} | _]}, Chunks = [{ChunkNo, _Chunk} | _Rest])
    when ChunkNo > Current ->
    return(next(Acc), Chunks);
return(Acc = {_, [{Current, _} | _]}, Chunks = [{ChunkNo, _Chunk} | _Rest])
    when ChunkNo < Current ->
    return(prev(Acc), Chunks);
return(Acc = {[], []}, [{ChunkNo, Chunk} | Rest]) ->
    return(insert({ChunkNo, Chunk}, Acc), Rest);
return({Pre, Post}, []) ->
    lists:foldl(fun({_, Value}, Acc) -> Value ++ Acc end, [], Pre)
    ++ lists:foldr(fun({_, Value}, Acc) -> Value ++ Acc end, [], Post).

-spec process(ParentPid :: pid(),
              ParentRef :: reference(),
              Fn :: fun((any()) -> any()),
              Timeout :: pos_integer()) ->
                 ok | no_return().
process(ParentPid, ParentRef, Fn, Timeout) ->
    process_flag(trap_exit, true),
    receive
        {Ref, Chunk, ChunkNo} when Ref =:= ParentRef ->
            TimerRef = erlang:send_after(Timeout, self(), kill),
            Result = do_process(Fn, Chunk, []),
            erlang:cancel_timer(TimerRef),
            ParentPid ! {ParentRef, result, ChunkNo, Result},
            process(ParentPid, ParentRef, Fn, Timeout);
        {Ref, stop} when Ref =:= ParentRef ->
            ok;
        _ ->
            process(ParentPid, ParentRef, Fn, Timeout)
    end.

-spec do_process(Fn :: fun((any()) -> any()), list(), Acc :: list()) -> list().
do_process(Fn, [Item | Rest], Acc) ->
    do_process(Fn, Rest, [Fn(Item) | Acc]);
do_process(_, [], Acc) ->
    Acc.

-spec do_pmap(fun((any()) -> any()), list(), Opts :: options()) -> {ok, list()} | error.
do_pmap(Fn, List, Opts) ->
    PidsRefs =
        [spawn_monitor(pmap2_zipper_pool,
                       process,
                       [Opts#options.parent_pid,
                        Opts#options.parent_ref,
                        Fn,
                        Opts#options.fun_timeout])
         || _ <- lists:seq(1, Opts#options.max_process_count)],
    Pids = [ChildPid || {ChildPid, _} <- PidsRefs],
    Refs = [ChildRef || {_, ChildRef} <- PidsRefs],
    RefsMap = maps:from_keys(Refs, undefined),
    Continuation = take(List, Opts#options.chunk_length, 1),
    ParentRef = Opts#options.parent_ref,
    ok = iter_pmap(Continuation, {[], Pids}, ParentRef),
    lists:foreach(fun(Pid) -> Pid ! {ParentRef, stop} end, Pids),
    case catch complete_gather([], RefsMap, ParentRef, maps:size(RefsMap)) of
        error ->
            lists:foreach(fun({Pid, Ref}) ->
                             true = demonitor(Ref),
                             true = exit(Pid, kill)
                          end,
                          PidsRefs),
            flush_inbox(maps:put(ParentRef, undefined, RefsMap)),
            error;
        Chunks ->
            {ok, return({[], []}, Chunks)}
    end.

-spec iter_pmap(Continuation :: cps(),
                Pids :: {[pid()], [pid()]},
                ParentRef :: reference()) ->
                   ok.
iter_pmap({continue, Chunk, ChunkNo, NextChunk}, {PidsPost, [Pid | Pids]}, ParentRef) ->
    Pid ! {ParentRef, Chunk, ChunkNo},
    iter_pmap(erlang:apply(pmap2_zipper_pool, take, NextChunk),
              {[Pid | PidsPost], Pids},
              ParentRef);
iter_pmap(done, _, _) ->
    ok;
iter_pmap(Continuation, {PidsPost, []}, ParentRef) ->
    iter_pmap(Continuation, {[], PidsPost}, ParentRef).

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

-spec complete_gather(Acc :: list(),
                      Refs :: map(),
                      ParentRef :: reference(),
                      WorkersRunning :: non_neg_integer()) ->
                         Acc :: list() | no_return().
complete_gather(Acc, _, _, 0) ->
    Acc;
complete_gather(Acc, Refs, ParentRef, WorkersRunning) ->
    receive
        {Ref, result, ChunkNo, Result} when Ref =:= ParentRef ->
            complete_gather([{ChunkNo, Result} | Acc], Refs, ParentRef, WorkersRunning);
        {'DOWN', ChildRef, process, _, Reason} when is_map_key(ChildRef, Refs) ->
            case Reason of
                normal ->
                    complete_gather(Acc, Refs, ParentRef, WorkersRunning - 1);
                _ ->
                    throw(error)
            end
    end.

-spec take(list(), ToTake :: pos_integer(), NextChunkNo :: pos_integer()) -> cps().
take(List, ToTake, NextChunkNo) ->
    case do_take(List, ToTake, []) of
        {[], []} ->
            done;
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
