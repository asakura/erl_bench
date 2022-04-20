-module(flush).

-export([flush_inbox/1, flush_inbox_sparse/1, flush_inbox_opt/1, flush_with_set_remove/1,
         flush_with_set_keep/1]).

flush_inbox([H | Rest]) ->
    receive
        {H, _, _, _} when is_reference(H) ->
            flush_inbox(Rest);
        {'EXIT', H, _} when is_pid(H) ->
            flush_inbox(Rest)
    after 0 ->
        flush_inbox(Rest)
    end;
flush_inbox([]) ->
    ok.

flush_inbox_sparse([Ref | Rest]) when is_reference(Ref) ->
    receive
        {Ref, _, _, _} ->
            flush_inbox_sparse(Rest)
    after 0 ->
        flush_inbox_sparse(Rest)
    end;
flush_inbox_sparse([Pid | Rest]) when is_pid(Pid) ->
    receive
        {'EXIT', Pid, _} ->
            flush_inbox_sparse(Rest)
    after 0 ->
        flush_inbox_sparse(Rest)
    end;
flush_inbox_sparse([]) ->
    ok.

flush_inbox_opt([H | Rest]) ->
    receive
        {Y, _, _, _} when is_reference(H), H =:= Y ->
            flush_inbox_opt(Rest);
        {'EXIT', Y, _} when is_pid(H), H =:= Y ->
            flush_inbox_opt(Rest)
    after 0 ->
        flush_inbox_opt(Rest)
    end;
flush_inbox_opt([]) ->
    ok.

flush_with_set_remove(Set) ->
    receive
        {Y, _, _, _} when is_reference(Y) andalso is_map_key(Y, Set) ->
            flush_with_set_remove(maps:remove(Y, Set));
        {'EXIT', Y, _} when is_pid(Y) andalso is_map_key(Y, Set) ->
            flush_with_set_remove(maps:remove(Y, Set))
    after 0 ->
        ok
    end.

flush_with_set_keep(Set) ->
    receive
        {Y, _, _, _} when is_reference(Y) andalso is_map_key(Y, Set) ->
            flush_with_set_keep(Set);
        {'EXIT', Y, _} when is_pid(Y) andalso is_map_key(Y, Set) ->
            flush_with_set_keep(Set)
    after 0 ->
        ok
    end.
