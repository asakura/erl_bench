defmodule ProcessCopyLiteral do
  @small_list [1, 2, 3]
  @huge_list Enum.to_list(1..1_000_000)
  @small_map %{1 => 1, 2 => 2, 3 => 3}
  @huge_map Enum.with_index(@huge_list) |> Enum.into(%{})

  def test_spawn(nil), do: do_spawn(nil)
  def test_spawn(:small_list), do: do_spawn(@small_list)
  def test_spawn(:huge_list), do: do_spawn(@huge_list)
  def test_spawn(:small_map), do: do_spawn(@small_map)
  def test_spawn(:huge_map), do: do_spawn(@huge_map)

  def do_spawn(input) do
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
  end

  def test_spawn_monitor(nil), do: do_spawn_monitor(nil)
  def test_spawn_monitor(:small_list), do: do_spawn_monitor(@small_list)
  def test_spawn_monitor(:huge_list), do: do_spawn_monitor(@huge_list)
  def test_spawn_monitor(:small_map), do: do_spawn_monitor(@small_map)
  def test_spawn_monitor(:huge_map), do: do_spawn_monitor(@huge_map)

  def do_spawn_monitor(input) do
    {_pid, ref} =
      spawn_monitor(fn ->
        ret = is_nil(input)
        ret
      end)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    end
  end

  def test_spawn_link(nil), do: do_spawn_link(nil)
  def test_spawn_link(:small_list), do: do_spawn_link(@small_list)
  def test_spawn_link(:huge_list), do: do_spawn_link(@huge_list)
  def test_spawn_link(:small_map), do: do_spawn_link(@small_map)
  def test_spawn_link(:huge_map), do: do_spawn_link(@huge_map)

  def do_spawn_link(input) do
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
end

Benchee.run(
  %{
    "spawn" => &ProcessCopyLiteral.test_spawn/1,
    "spawn monitor" => &ProcessCopyLiteral.test_spawn_monitor/1,
    "spawn link" => &ProcessCopyLiteral.test_spawn_link/1
  },
  inputs: %{
    "1. No scope to copy" => nil,
    "2. 3 elem. list" => :small_list,
    "3. 3 key map" => :small_map,
    "4. 1M list" => :huge_list,
    "5. 1M map" => :huge_map
  },
  warmup: 10,
  time: 20
)
