-module(pmap_v6_pool_zipper_inline).

-export([pmap/3, pmap/4]).

-compile(inline).
-compile({inline_size, 100}).

-type funfun() :: fun((term()) -> term()).
-type process_count() :: pos_integer().
-type input_list() :: [term()].

%% Features comparing to pmap_v1
%% 1. flush inbox
%% 2. spawn link
%% 3. fail at first error
%% 4. process pool

-record(options,
        {max_process_count,
         chunk_length,
         parent_pid,
         parent_ref,
         final_gather_timeout,
         worker_timeout}).
-record(pool, {pids = [], allocated = [], ref}).

-spec pmap(funfun(), input_list(), process_count()) -> [term()].
pmap(Fn, List, ProcessCount) when is_integer(ProcessCount) ->
    Opts =
        #options{max_process_count = ProcessCount,
                 chunk_length = 100,
                 final_gather_timeout = 1000,
                 worker_timeout = 100},
    pmap(Fn, List, Opts);
pmap(Fn, List, Opts) ->
    ParentPid = self(),
    ParentRef = make_ref(),
    NewOpts = Opts#options{parent_pid = ParentPid, parent_ref = ParentRef},
    Continuation = take(List, Opts#options.chunk_length),
    case do_pmap(Continuation, Opts#options.max_process_count, Fn, NewOpts) of
        error ->
            error;
        {ok, Chunks} ->
            {ok, to_list(Chunks)}
    end.

to_list({Pre, Post}) ->
    lists:foldl(fun({_, Value}, Acc) -> Value ++ Acc end, [], Pre)
    ++ lists:foldr(fun({_, Value}, Acc) -> Value ++ Acc end, [], Post).

pmap(Fn, List, ProcessCount, ChunkLength)
    when is_integer(ProcessCount), is_integer(ChunkLength) ->
    Opts =
        #options{max_process_count = ProcessCount,
                 chunk_length = ChunkLength,
                 final_gather_timeout = 1000,
                 worker_timeout = 100},
    pmap(Fn, List, Opts).

process(ParentPid, ParentRef, Fn, Timeout) ->
    fun() ->
       process_flag(trap_exit, true),
       Fun = fun InnerLoop() ->
                     receive
                         {ParentRef, Chunk, ChunkNo} ->
                             {ok, TRef} = timer:kill_after(Timeout),
                             try [Fn(X) || X <- Chunk] of
                                 Result -> ParentPid ! {ParentRef, result, self(), ChunkNo, Result}
                             catch
                                 _ -> ParentPid ! {ParentRef, error, self()}
                             end,
                             {ok, cancel} = timer:cancel(TRef),
                             InnerLoop();
                         {ParentRef, stop} -> ParentPid ! {ParentRef, stopped, self()};
                         _ -> InnerLoop()
                     end
             end,
       Fun()
    end.

pool_init(PoolSize, ParentPid, ParentRef, Fn, WorkerTimeout) ->
    Pids =
        [spawn_link(process(ParentPid, ParentRef, Fn, WorkerTimeout))
         || _ <- lists:seq(1, PoolSize)],
    {ok,
     #pool{pids = Pids,
           allocated = [],
           ref = ParentRef}}.

pool_deallocate(Pool) ->
    Ref = Pool#pool.ref,
    Workers = Pool#pool.pids,
    ok = pool_stop_gracefully(Workers, Ref),
    StoppedWorkers = pool_wait_stopping(Workers, Ref, []),
    AllocatedWorkers = Pool#pool.allocated,
    PidsToKill = (Workers -- StoppedWorkers) ++ AllocatedWorkers,
    ok = pool_kill_brutally(PidsToKill),
    ok = pool_flush_inbox([Ref] ++ Workers ++ AllocatedWorkers).

pool_stop_gracefully(Pids, Ref) ->
    lists:foreach(fun(Pid) ->
                     Pid ! {Ref, stop},
                     Pid
                  end,
                  Pids),
    ok.

pool_kill_brutally(Pids) ->
    lists:foreach(fun(Pid) ->
                     unlink(Pid),
                     exit(Pid, kill)
                  end,
                  Pids),
    ok.

pool_wait_stopping([Pid | LeftPids], Ref, Stopped) ->
    receive
        {Ref, stopped, Pid} ->
            pool_wait_stopping(LeftPids, Ref, [Pid | Stopped])
    after 10 ->
        pool_wait_stopping(LeftPids, Ref, Stopped)
    end;
pool_wait_stopping([], _, Stopped) ->
    Stopped.

pool_flush_inbox([Ref | Rest]) when is_reference(Ref) ->
    receive
        {Ref, _, _, _} ->
            pool_flush_inbox(Rest)
    after 0 ->
        pool_flush_inbox(Rest)
    end;
pool_flush_inbox([Pid | Rest]) ->
    receive
        {'EXIT', Pid, _} ->
            pool_flush_inbox(Rest)
    after 0 ->
        pool_flush_inbox(Rest)
    end;
pool_flush_inbox([]) ->
    ok.

pool_checkout(Pool) ->
    case Pool of
        #pool{pids = [Pid | Pids]} ->
            {ok, Pool#pool{pids = Pids, allocated = [Pid | Pool#pool.allocated]}, Pid};
        #pool{pids = []} ->
            error
    end.

pool_checkin(Pool, Pid) ->
    {ok, Pool#pool{pids = [Pid | Pool#pool.pids], allocated = Pool#pool.allocated -- [Pid]}}.

pool_vacant_workers(#pool{pids = Pids}) ->
    length(Pids).

pool_busy_workers(#pool{allocated = Allocated}) ->
    length(Allocated).

pool_wait(Pool, Acc, Timeout) ->
    pool_wait(pool_busy_workers(Pool), Pool, Acc, Timeout).

pool_wait(0, Pool, Acc, _) ->
    {ok, pool_vacant_workers(Pool), Pool, Acc};
pool_wait(Left, Pool, Acc, Timeout) ->
    Ref = Pool#pool.ref,
    receive
        {Ref, result, WorkerPid, ChunkNo, Result} ->
            {ok, NewPool} = pool_checkin(Pool, WorkerPid),
            NewAcc = insert_chunk(ChunkNo, Result, Acc),
            pool_wait(Left - 1, NewPool, NewAcc, Timeout);
        {'EXIT', WorkerPid, _} ->
            NewPool = Pool#pool{allocated = Pool#pool.allocated -- [WorkerPid]},
            throw({error, NewPool})
    after Timeout ->
        case Timeout of
            0 ->
                pool_wait(0, Pool, Acc, Timeout);
            _ ->
                throw({error, Pool})
        end
    end.

dispatch(Pool, Chunk, ChunkNo) ->
    {ok, NewPool, Worker} = pool_checkout(Pool),
    Worker ! {Pool#pool.ref, Chunk, ChunkNo},
    {ok, NewPool}.

do_pmap(Continuation, PoolSize, Fn, Opts) ->
    TrapExit = process_flag(trap_exit, true),
    {ok, Pool} =
        pool_init(PoolSize,
                  Opts#options.parent_pid,
                  Opts#options.parent_ref,
                  Fn,
                  Opts#options.worker_timeout),
    {Result, NewPool} = catch do_pmap(Continuation, PoolSize, Pool, _Acc = {[], []}, Opts),
    ok = pool_deallocate(NewPool),
    process_flag(trap_exit, TrapExit),
    Result.

do_pmap(Continuation, _VacantWorkers = 0, Pool, Acc, Opts) ->
    {ok, VacantWorkers, NewPool, NewAcc} = pool_wait(Pool, Acc, 0),
    do_pmap(Continuation, VacantWorkers, NewPool, NewAcc, Opts);
do_pmap({continue, Chunk, ChunkNo, NextChunkFn}, VacantWorkers, Pool, Acc, Opts) ->
    {ok, NewPool} = dispatch(Pool, Chunk, ChunkNo),
    do_pmap(NextChunkFn(), VacantWorkers - 1, NewPool, Acc, Opts);
do_pmap({done, _}, _, Pool, Acc, Opts) ->
    {ok, _, NewPool, NewAcc} = pool_wait(Pool, Acc, Opts#options.final_gather_timeout),
    {{ok, NewAcc}, NewPool}.

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

insert(Val, {Pre, Post}) ->
    {Pre, [Val | Post]}.

prev({[H | T], Post}) ->
    {T, [H | Post]}.

next({Pre, [H | T]}) ->
    {[H | Pre], T}.

insert_chunk(Index, Value, ZList = {[{Last, _} | _], [{Current, _} | _]})
    when Index > Last andalso Index =< Current ->
    insert({Index, Value}, ZList);
insert_chunk(Index, Value, ZList = {[], [{Current, _} | _]}) when Index < Current ->
    insert({Index, Value}, ZList);
insert_chunk(Index, Value, ZList = {[{Last, _} | _], []}) when Index > Last ->
    insert({Index, Value}, ZList);
insert_chunk(Index, Value, ZList = {_, [{Current, _} | _]}) when Index > Current ->
    insert_chunk(Index, Value, next(ZList));
insert_chunk(Index, Value, ZList = {_, [{Current, _} | _]}) when Index < Current ->
    insert_chunk(Index, Value, prev(ZList));
insert_chunk(Index, Value, ZList = {[], []}) ->
    insert({Index, Value}, ZList).
