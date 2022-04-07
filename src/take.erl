-module(take).

-export([take_all/1, take1/2, take5/2, take10/2]).

take_all({continue, _, _, Next}) ->
    take_all(Next());
take_all({done, _}) ->
    ok.

take1(List, {ToTake, NextChunkNo}) ->
    case take1(List, ToTake, []) of
        {[], _, []} ->
            {done, NextChunkNo};
        {Chunk, []} ->
            {continue, Chunk, NextChunkNo, fun() -> {done, NextChunkNo} end};
        {Chunk, Rest} ->
            {continue, Chunk, NextChunkNo, fun() -> take1(Rest, {ToTake, NextChunkNo + 1}) end}
    end;
take1(List, ToTake) ->
    take1(List, {ToTake, 1}).

take1(Rest, 0, Chunk) ->
    {Chunk, Rest};
take1([H | Rest], Left, Chunk) ->
    take1(Rest, Left - 1, [H | Chunk]);
take1([], _, Chunk) ->
    {Chunk, []}.



take5(List, {ToTake, NextChunkNo}) ->
    case take5(List, ToTake, []) of
        {[], _, []} ->
            {done, NextChunkNo};
        {Chunk, []} ->
            {continue, Chunk, NextChunkNo, fun() -> {done, NextChunkNo} end};
        {Chunk, Rest} ->
            {continue, Chunk, NextChunkNo, fun() -> take5(Rest, {ToTake, NextChunkNo + 1}) end}
    end;
take5(List, ToTake) ->
    take5(List, {ToTake, 1}).

take5(Rest, 0, Chunk) ->
    {Chunk, Rest};
take5([H1, H2, H3, H4, H5 | Rest], Left, Chunk) ->
    take5(Rest, Left - 5, [H5, H4, H3, H2, H1 | Chunk]);
take5([H | Rest], Left, Chunk) ->
    take5(Rest, Left - 1, [H | Chunk]);
take5([], _, Chunk) ->
    {Chunk, []}.


take10(List, {ToTake, NextChunkNo}) ->
    case take10(List, ToTake, []) of
        {[], _, []} ->
            {done, NextChunkNo};
        {Chunk, []} ->
            {continue, Chunk, NextChunkNo, fun() -> {done, NextChunkNo} end};
        {Chunk, Rest} ->
            {continue, Chunk, NextChunkNo, fun() -> take10(Rest, {ToTake, NextChunkNo + 1}) end}
    end;
take10(List, ToTake) ->
    take10(List, {ToTake, 1}).

take10(Rest, 0, Chunk) ->
    {Chunk, Rest};
take10([H1, H2, H3, H4, H5, H6, H7, H8, H9, H10 | Rest], Left, Chunk) ->
    take10(Rest, Left - 10, [H10, H9, H8, H7, H6, H5, H4, H3, H2, H1 | Chunk]);
take10([H | Rest], Left, Chunk) ->
    take10(Rest, Left - 1, [H | Chunk]);
take10([], _, Chunk) ->
    {Chunk, []}.
