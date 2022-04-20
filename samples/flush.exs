generate = fn ->
  refs = Enum.map(Enum.to_list(1..500), fn _ -> make_ref() end)
  pids = Enum.map(Enum.to_list(1..500), fn _ -> spawn(fn -> :ok end) end)

  Enum.zip(refs, pids)
  |> Enum.reduce([], fn {ref, pid}, acc -> [ref | [pid | acc]] end)
end

input_list = Enum.shuffle(generate.())
map_set = for i <- input_list, into: %{} do
  {i, nil}
end

Benchee.run(
  %{
    "1. flush_inbox/1" => fn {input, _} ->
      :flush.flush_inbox(input)
    end,
    "2. flush_inbox_sparse/1" => fn {input, _} ->
      :flush.flush_inbox_sparse(input)
    end,
    "3. flush_inbox_opt/1" => fn {input, _} ->
      :flush.flush_inbox_opt(input)
    end,
    "4. flush_with_set_remove/1" => fn {_, input} ->
      :flush.flush_with_set_remove(input)
    end,
    "5. flush_with_set_keep/1" => fn {_, input} ->
      :flush.flush_with_set_keep(input)
    end,
  },
  inputs: %{
    "0. 1k" => {input_list, map_set}
  },
  before_each: fn {input_list, _} = input ->
    for i <- Enum.shuffle(input_list) do
      cond do
        is_reference(i) ->
          send(self(), {i, nil, nil, nil})
        is_pid(i) ->
          send(self(), {:'EXIT', i, nil})
      end
    end

    :erlang.garbage_collect()

    input
  end,
  warmup: 5,
  time: 20,
  reduction_time: 2,
  memory_time: 2
)
