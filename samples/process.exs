small_input = [1, 2, 3]
huge_input = Enum.to_list(1..1_000_000)

Benchee.run(
  %{
    "spawn" => fn input ->
      parent = self()
      ref = make_ref()

      spawn(fn ->
        hd(input)
        send(parent, {:ok, ref})
        :ok
      end)

      receive do
        {:ok, ^ref} -> :ok
      end
    end,
    "spawn monitor" => fn input ->
      {_pid, ref} =
        spawn_monitor(fn ->
          hd(input)
          :ok
        end)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end
    end,
    "spawn link" => fn input ->
      Process.flag(:trap_exit, true)

      pid =
        spawn_link(fn ->
          hd(input)
          :ok
        end)

      receive do
        {:EXIT, ^pid, _} -> :ok
      end
    end
  },
  inputs: %{
    "Small" => small_input,
    "Huge" => huge_input
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  warmup: 2,
  time: 5
)
