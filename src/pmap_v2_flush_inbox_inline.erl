-module(pmap_v2_flush_inbox_inline).

-export([pmap/3, pmap/4]).

-compile(inline).
-compile({inline_size, 100}).

-type funfun() :: fun((term()) -> term()).
-type process_count() :: pos_integer().
-type input_list() :: [term()].

%% Features comparing to pmap_v1
%% 1. flush inbox

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
    ParentPid = self(),
    ParentRef = make_ref(),
    NewOpts = Opts#options{parent_pid = ParentPid, parent_ref = ParentRef},
    Continuation = take(List, Opts#options.chunk_length),
    {Chunks, LastChunkNo, LastChunkSize} =
        do_pmap(Continuation, Opts#options.max_process_count, Fn, NewOpts),
    flush_inbox(ParentRef),
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

flush_inbox(ParentRef) ->
    receive
        {ParentRef, _, _, _} ->
            flush_inbox(ParentRef)
    after 0 ->
        undefined
    end.

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
    do_pmap(Continuation, ProcessCount, _Refs = #{}, _Acc = [], Fn, Opts).

do_pmap(Continuation, 0, Refs, Acc, Fn, Opts) ->
    Running = maps:size(Refs),
    {NewAcc, LeftRunning, NewRefs} =
        partial_gather(Acc, Refs, Running, Opts#options.parent_ref, 0),
    do_pmap(Continuation, Running - LeftRunning, NewRefs, NewAcc, Fn, Opts);
do_pmap({continue, Chunk, ChunkNo, NextChunk}, ProcessCount, Refs, Acc, Fn, Opts) ->
    {Pid, MonitorRef} =
        spawn_monitor(process(Opts#options.parent_pid,
                              Opts#options.parent_ref,
                              ChunkNo,
                              Fn,
                              Chunk)),
    {ok, TRef} = timer:kill_after(Opts#options.fun_timeout, Pid),
    NewRefs = maps:put(MonitorRef, {ChunkNo, TRef, Pid}, Refs),
    do_pmap(NextChunk(), ProcessCount - 1, NewRefs, Acc, Fn, Opts);
do_pmap({done, LastChunkNo, LastChunkSize}, _, Refs, Acc, _, Opts) ->
    {NewAcc, _, RefsLeft} =
        partial_gather(Acc,
                       Refs,
                       maps:size(Refs),
                       Opts#options.parent_ref,
                       Opts#options.final_gather_timeout),
    maps:foreach(fun(MonitorRef, {_, TRef, Pid}) ->
                    timer:cancel(TRef),
                    demonitor(MonitorRef, [flush]),
                    exit(Pid, kill)
                 end,
                 RefsLeft),
    {NewAcc, LastChunkNo, LastChunkSize}.

partial_gather(Acc, Refs, 0, _, _) ->
    {Acc, maps:size(Refs), Refs};
partial_gather(Acc, Refs, Left, ParentRef, Timeout) ->
    receive
        {ParentRef, result, ChunkNo, Data} ->
            partial_gather([{ChunkNo, Data} | Acc], Refs, Left, ParentRef, Timeout);
        {'DOWN', MonitorRef, process, _, normal} ->
            {{_, TRef, _}, NewRefs} = maps:take(MonitorRef, Refs),
            timer:cancel(TRef),
            partial_gather(Acc, NewRefs, Left - 1, ParentRef, Timeout);
        {'DOWN', MonitorRef, process, _, _} ->
            {{ChunkNo, TRef, _}, NewRefs} = maps:take(MonitorRef, Refs),
            timer:cancel(TRef),
            partial_gather([{ChunkNo, timeout} | Acc], NewRefs, Left - 1, ParentRef, Timeout)
    after Timeout ->
        partial_gather(Acc, Refs, 0, ParentRef, 0)
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
