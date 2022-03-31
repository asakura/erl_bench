-module(pmap_v4_fail_at_first_error).

-export([pmap/3, pmap/4]).

-type funfun() :: fun((term()) -> term()).
-type process_count() :: pos_integer().
-type input_list() :: [term()].

%% Features comparing to pmap_v1
%% 1. flush inbox
%% 2. spawn link
%% 3. fail at first error

-record(options,
        {max_process_count,
         chunk_length,
         parent_pid,
         parent_ref,
         final_gather_timeout,
         fun_timeout}).

-spec pmap(funfun(), input_list(), process_count()) -> [term()].
pmap(Fn, List, ProcessCount) when is_integer(ProcessCount) ->
    Opts =
        #options{max_process_count = ProcessCount,
                 chunk_length = 100,
                 final_gather_timeout = 1000,
                 fun_timeout = 100},
    pmap(Fn, List, Opts);
pmap(Fn, List, Opts) ->
    TrapExit = process_flag(trap_exit, true),
    ParentPid = self(),
    ParentRef = make_ref(),
    NewOpts = Opts#options{parent_pid = ParentPid, parent_ref = ParentRef},
    Continuation = take(List, Opts#options.chunk_length),
    {Result, Pids} = do_pmap(Continuation, Opts#options.max_process_count, Fn, NewOpts),
    try Result of
        error ->
            error;
        {ok, Chunks, LastChunkNo} ->
            ChunksMap = proplists:to_map(Chunks),
            {ok, return(LastChunkNo, [], ChunksMap)}
    after
        flush_inbox([ParentRef | Pids]),
        process_flag(trap_exit, TrapExit)
    end.

pmap(Fn, List, ProcessCount, ChunkLength)
    when is_integer(ProcessCount), is_integer(ChunkLength) ->
    Opts =
        #options{max_process_count = ProcessCount,
                 chunk_length = ChunkLength,
                 final_gather_timeout = 1000,
                 fun_timeout = 100},
    pmap(Fn, List, Opts).

flush_inbox([Ref | Rest]) when is_reference(Ref) ->
    receive
        {Ref, _, _, _} ->
            flush_inbox(Rest)
    after 0 ->
        flush_inbox(Rest)
    end;
flush_inbox([Pid | Rest]) ->
    receive
        {'EXIT', Pid, _} ->
            flush_inbox(Rest)
    after 0 ->
        flush_inbox(Rest)
    end;
flush_inbox([]) ->
    ok.

return(0, Acc, _) ->
    Acc;
return(Left, Acc, Chunks) ->
    case maps:take(Left, Chunks) of
        {Chunk, ChunksLeft} ->
            return(Left - 1, Chunk ++ Acc, ChunksLeft)
    end.

process(ParentPid, ParentRef, ChunkNo, Fn, Chunk) ->
    fun() ->
       try [Fn(X) || X <- Chunk] of
           Result -> ParentPid ! {ParentRef, result, ChunkNo, Result}
       catch
           _ -> ok
       end
    end.

do_pmap(Continuation, ProcessCount, Fn, Opts) ->
    {Result, Pids} =
        catch do_pmap(Continuation, ProcessCount, _Pids = #{}, _Acc = [], Fn, Opts),
    maps:foreach(fun(Pid, {_, TRef}) ->
                    timer:cancel(TRef),
                    unlink(Pid),
                    exit(Pid, kill)
                 end,
                 Pids),
    {Result, maps:keys(Pids)}.

do_pmap(Continuation, 0, Pids, Acc, Fn, Opts) ->
    Running = maps:size(Pids),
    {NewAcc, LeftRunning, NewPids} =
        partial_gather(Acc, Pids, Running, Opts#options.parent_ref, 0),
    do_pmap(Continuation, Running - LeftRunning, NewPids, NewAcc, Fn, Opts);
do_pmap({continue, Chunk, ChunkNo, NextChunk}, ProcessCount, Pids, Acc, Fn, Opts) ->
    Pid = spawn_link(process(Opts#options.parent_pid,
                             Opts#options.parent_ref,
                             ChunkNo,
                             Fn,
                             Chunk)),
    {ok, TRef} = timer:kill_after(Opts#options.fun_timeout, Pid),
    NewPids = maps:put(Pid, {ChunkNo, TRef}, Pids),
    do_pmap(NextChunk(), ProcessCount - 1, NewPids, Acc, Fn, Opts);
do_pmap({done, LastChunkNo}, _, Pids, Acc, _, Opts) ->
    {NewAcc, _, PidsLeft} =
        partial_gather(Acc,
                       Pids,
                       maps:size(Pids),
                       Opts#options.parent_ref,
                       Opts#options.final_gather_timeout),
    {{ok, NewAcc, LastChunkNo}, PidsLeft}.

partial_gather(continue, Acc, Pids) ->
    {Acc, maps:size(Pids), Pids};
partial_gather(exit, _, Pids) ->
    throw({error, Pids}).

partial_gather(Acc, Pids, 0, _, _) ->
    partial_gather(continue, Acc, Pids);
partial_gather(Acc, Pids, Left, ParentRef, Timeout) ->
    receive
        {ParentRef, result, ChunkNo, Data} ->
            partial_gather([{ChunkNo, Data} | Acc], Pids, Left, ParentRef, Timeout);
        {'EXIT', ChildPid, normal} ->
            {{_, TRef}, NewPids} = maps:take(ChildPid, Pids),
            timer:cancel(TRef),
            partial_gather(Acc, NewPids, Left - 1, ParentRef, Timeout);
        {'EXIT', ChildPid, _} ->
            {{_, TRef}, NewPids} = maps:take(ChildPid, Pids),
            timer:cancel(TRef),
            partial_gather(exit, Acc, NewPids)
    after Timeout ->
        partial_gather(Acc, Pids, 0, ParentRef, 0)
    end.

take(List, {ToTake, NextChunkNo}) ->
    case take(List, ToTake, []) of
        {[], _, []} ->
            {done, NextChunkNo};
        {Chunk, []} ->
            {continue, Chunk, NextChunkNo, fun() -> {done, NextChunkNo} end};
        {Chunk, Rest} ->
            {continue, Chunk, NextChunkNo, fun() -> take(Rest, {ToTake, NextChunkNo + 1}) end}
    end;
take(List, ToTake) ->
    take(List, {ToTake, 1}).

take(Rest, 0, Chunk) ->
    {lists:reverse(Chunk), Rest};
take([Head | Rest], Left, Chunk) ->
    take(Rest, Left - 1, [Head | Chunk]);
take([], _, Chunk) ->
    {lists:reverse(Chunk), []}.
