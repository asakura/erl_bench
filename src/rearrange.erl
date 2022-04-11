-module(rearrange).

-export([zipper/1, zipper_insert_chunks/1, mapper_reduce/2, mapper_keep/2, mapper_insert_chunks/1]).

zipper({Pre, Post}) ->
    lists:foldl(fun({_, Value}, Acc) -> Value ++ Acc end, [], Pre)
    ++ lists:foldr(fun({_, Value}, Acc) -> Value ++ Acc end, [], Post).

zipper_insert_chunks(Chunks) ->
    lists:foldl(fun({ChunkNo, Chunk}, Acc) -> zipper_insert_chunk(ChunkNo, Chunk, Acc) end, {[], []}, Chunks).

insert(Val, {Pre, Post}) ->
    {Pre, [Val | Post]}.

prev({[H | T], Post}) ->
    {T, [H | Post]}.

next({Pre, [H | T]}) ->
    {[H | Pre], T}.

zipper_insert_chunk(Index, Value, ZList = {[{Last, _} | _], [{Current, _} | _]})
    when Index > Last andalso Index =< Current ->
    insert({Index, Value}, ZList);
zipper_insert_chunk(Index, Value, ZList = {[], [{Current, _} | _]}) when Index < Current ->
    insert({Index, Value}, ZList);
zipper_insert_chunk(Index, Value, ZList = {[{Last, _} | _], []}) when Index > Last ->
    insert({Index, Value}, ZList);
zipper_insert_chunk(Index, Value, ZList = {_, [{Current, _} | _]}) when Index > Current ->
    zipper_insert_chunk(Index, Value, next(ZList));
zipper_insert_chunk(Index, Value, ZList = {_, [{Current, _} | _]}) when Index < Current ->
    zipper_insert_chunk(Index, Value, prev(ZList));
zipper_insert_chunk(Index, Value, ZList = {[], []}) ->
    insert({Index, Value}, ZList).

mapper_reduce(Chunks, LastChunkNo) ->
    ChunksMap = proplists:to_map(Chunks),
    mapper_reduce(LastChunkNo, [], ChunksMap).

mapper_reduce(0, Acc, _) ->
    Acc;
mapper_reduce(Left, Acc, Chunks) ->
    {Chunk, ChunksLeft} = maps:take(Left, Chunks),
    mapper_reduce(Left - 1, Chunk ++ Acc, ChunksLeft).

mapper_keep(Chunks, LastChunkNo) ->
    ChunksMap = proplists:to_map(Chunks),
    mapper_keep(LastChunkNo, [], ChunksMap).

mapper_keep(0, Acc, _) ->
    Acc;
mapper_keep(Left, Acc, Chunks) ->
    Chunk = maps:get(Left, Chunks),
    mapper_keep(Left - 1, Chunk ++ Acc, Chunks).

mapper_insert_chunks(Chunks) ->
    lists:foldl(fun({ChunkNo, Chunk}, Acc) -> [{ChunkNo, Chunk}|Acc] end, [], Chunks).
