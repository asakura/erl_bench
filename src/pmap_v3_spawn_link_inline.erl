-module(pmap_v3_spawn_link_inline).

-export([pmap/3, pmap/4]).

-compile(inline).
-compile({inline_size, 100}).

-type funfun() :: fun((term()) -> term()).
-type process_count() :: pos_integer().
-type input_list() :: [term()].

%% Features comparing to pmap_v1
%% 1. flush inbox
%% 2. spawn link

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
    {Chunks, LastChunkNo, LastChunkSize, Pids} =
        do_pmap(Continuation, Opts#options.max_process_count, Fn, NewOpts),
    process_flag(trap_exit, TrapExit),
    flush_inbox([ParentRef | Pids]),
    {Acc, ChunksLeft} =
        case maps:take(LastChunkNo, proplists:to_map(Chunks)) of
            {timeout, ChunksLeft} ->
                {lists:duplicate(LastChunkSize, timeout), ChunksLeft};
            {Chunk, ChunksLeft} ->
                {Chunk, ChunksLeft}
        end,
    return(LastChunkNo - 1,
           Acc,
           ChunksLeft,
           lists:duplicate(Opts#options.chunk_length, timeout)).

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

return(0, Acc, _, _) ->
    Acc;
return(Left, Acc, Chunks, TimeoutChunk) ->
    case maps:take(Left, Chunks) of
        {timeout, NewChunks} ->
            return(Left - 1, TimeoutChunk ++ Acc, NewChunks, TimeoutChunk);
        {Chunk, NewChunks} ->
            return(Left - 1, Chunk ++ Acc, NewChunks, TimeoutChunk)
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
    do_pmap(Continuation, ProcessCount, _Pids = #{}, _Acc = [], Fn, Opts).

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
do_pmap({done, LastChunkNo, LastChunkSize}, _, Pids, Acc, _, Opts) ->
    {NewAcc, _, PidsLeft} =
        partial_gather(Acc,
                       Pids,
                       maps:size(Pids),
                       Opts#options.parent_ref,
                       Opts#options.final_gather_timeout),
    maps:foreach(fun(Pid, {_, TRef}) ->
                    timer:cancel(TRef),
                    unlink(Pid),
                    exit(Pid, kill)
                 end,
                 PidsLeft),
    {NewAcc, LastChunkNo, LastChunkSize, maps:keys(PidsLeft)}.

partial_gather(Acc, Pids, 0, _, _) ->
    {Acc, maps:size(Pids), Pids};
partial_gather(Acc, Pids, Left, ParentRef, Timeout) ->
    receive
        {ParentRef, result, ChunkNo, Data} ->
            partial_gather([{ChunkNo, Data} | Acc], Pids, Left, ParentRef, Timeout);
        {'EXIT', ChildPid, normal} ->
            {{_, TRef}, NewPids} = maps:take(ChildPid, Pids),
            timer:cancel(TRef),
            partial_gather(Acc, NewPids, Left - 1, ParentRef, Timeout);
        {'EXIT', ChildPid, _} ->
            {{ChunkNo, TRef}, NewPids} = maps:take(ChildPid, Pids),
            timer:cancel(TRef),
            partial_gather([{ChunkNo, timeout} | Acc], NewPids, Left - 1, ParentRef, Timeout)
    after Timeout ->
        partial_gather(Acc, Pids, 0, ParentRef, 0)
    end.

take(List, {ToTake, NextChunkNo}) ->
    case take(List, ToTake, []) of
        {[], _, []} ->
            {done, NextChunkNo, 0};
        {Chunk, []} ->
            {continue, Chunk, NextChunkNo, fun() -> {done, NextChunkNo, length(Chunk)} end};
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
