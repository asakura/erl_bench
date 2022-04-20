-module(flush_2).
-compile(export_all).

%% ==> {test,is_reference,{f,1},[{x,0}]}.
%%     {get_tuple_element,{x,1},0,{x,2}}.
%%     {test,is_eq_exact,{f,1},[{tr,{x,0},reference},{x,2}]}.
example_fn_fast(H, {Y}) when is_reference(H), H =:= Y ->
    H;
example_fn_fast(H, {Y, _}) when is_pid(H), H =:= Y ->
    H.

%%     {get_tuple_element,{x,1},0,{x,2}}.
%%     {test,is_eq_exact,{f,5},[{x,2},{x,0}]}.
%% ==> {test,is_reference,{f,5},[{x,0}]}.
example_fn_slow(H, {H}) when is_reference(H) ->
    H;
example_fn_slow(H, {H, _}) when is_pid(H) ->
    H.

example_case_fast(H, X) ->
    case X of
        %% ==> {test,is_reference,{f,13},[{x,0}]}.
        %%     {get_tuple_element,{x,1},0,{x,2}}.
        %%     {test,is_eq_exact,{f,13},[{tr,{x,0},reference},{x,2}]}.
        {Y} when is_reference(H), H =:= Y ->
            Y;
        {Y, _} when is_pid(H), H =:= Y ->
            Y
    end.

example_case_slow(H, X) ->
    case X of
        %%     {get_tuple_element,{x,1},0,{x,2}}.
        %%     {test,is_eq_exact,{f,18},[{x,2},{x,0}]}.
        %% ==> {test,is_reference,{f,18},[{x,0}]}.
        {H} when is_reference(H) ->
            H;
        {H, _} when is_pid(H) ->
            H
    end.

example_recv_fast(H) ->
    receive
        %%     {get_tuple_element,{x,0},0,{x,0}}.
        %% ==> {test,is_reference,{f,25},[{y,0}]}.
        %%     {test,is_eq_exact,{f,25},[{tr,{y,0},reference},{x,0}]}.
        %%     {jump,{f,24}}.
        {Y} when is_reference(H), H =:= Y ->
            H;
        %%     {get_tuple_element,{x,0},0,{x,0}}.
        %%     {test,is_pid,{f,25},[{y,0}]}.
        %%     {test,is_eq_exact,{f,25},[{tr,{y,0},pid},{x,0}]}.
        {Y, _} when is_pid(H), H =:= Y ->
            H
    %% {label,24}.
    %%   remove_message.
    %%   {move,{y,0},{x,0}}.
    %%   {deallocate,1}.
    %%   return.
    end.

example_recv(H) ->
    receive
        %% ==> {test,is_reference,{f,32},[{y,0}]}.
        %%     {get_tuple_element,{x,0},0,{x,0}}.
        {Y} when is_reference(H) ->
            Y;
        {Y, _} when is_pid(H) ->
            Y
    end.

example_recv_slow(H) ->
    receive
        %%     {get_tuple_element,{x,0},0,{x,0}}.
        %%     {test,is_eq_exact,{f,39},[{x,0},{y,0}]}.
        %% ==> {test,is_reference,{f,39},[{y,0}]}.
        %%     remove_message.
        %%     {move,{y,0},{x,0}}.
        %%     {deallocate,1}.
        %%     return.
        {H} when is_reference(H) ->
            H;
        %%     {get_tuple_element,{x,0},0,{x,0}}.
        %%     {test,is_eq_exact,{f,39},[{x,0},{y,0}]}.
        %%     {test,is_reference,{f,39},[{y,0}]}.
        %%     remove_message.
        %%     {move,{y,0},{x,0}}.
        %%     {deallocate,1}.
        %%     return.
        {H, _} when is_pid(H) ->
            H
    end.

%% Name                      ips        average  deviation         median         99th %
%% example fn fast       17.05 M       58.64 ns  ±3183.37%          57 ns          65 ns
%% example fn slow       16.90 M       59.19 ns  ±3232.34%          58 ns          63 ns

%% Comparison:
%% example fn fast       17.05 M
%% example fn slow       16.90 M - 1.01x slower +0.55 ns

%% Name                      ips        average  deviation         median         99th %
%% example case fast     17.15 M       58.30 ns  ±3282.01%          57 ns          63 ns
%% example case slow     17.14 M       58.33 ns  ±3331.75%          57 ns          69 ns

%% Comparison:
%% example case fast     17.15 M
%% example case slow     17.14 M - 1.00x slower +0.0282 ns

%% Name                      ips        average  deviation         median         99th %
%% example recv fast      8.11 M      123.33 ns  ±3743.48%         119 ns         154 ns
%% example recv slow      8.09 M      123.54 ns  ±3647.40%         119 ns         154 ns

%% Comparison:
%% example recv fast      8.11 M
%% example recv slow      8.09 M - 1.00x slower +0.21 ns
