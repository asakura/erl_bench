small_list = [1, 2, 3]
huge_list = Enum.to_list(1..1_000_000)
small_map = %{1 => 1, 2 => 2, 3 => 3}
huge_map = Enum.with_index(huge_list) |> Enum.into(%{})

Benchee.run(
  %{
    "spawn" => fn input ->
      parent = self()
      ref = make_ref()

      spawn(fn ->
        ret = is_nil(input)
        send(parent, {:ok, ref})
        ret
      end)

      receive do
        {:ok, ^ref} -> :ok
      end
    end,
    "spawn monitor" => fn input ->
      {_pid, ref} =
        spawn_monitor(fn ->
          ret = is_nil(input)
          ret
        end)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end
    end,
    "spawn link" => fn input ->
      Process.flag(:trap_exit, true)

      pid =
        spawn_link(fn ->
          ret = is_nil(input)
          ret
        end)

      receive do
        {:EXIT, ^pid, _} -> :ok
      end
    end
  },
  inputs: %{
    "1. No scope to copy" => nil,
    "2. 3 elem. list" => small_list,
    "3. 3 key map" => small_map,
    "4. 1M list" => huge_list,
    "5. 1M map" => huge_map
  },
  warmup: 10,
  time: 20
)
