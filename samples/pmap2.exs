medium_list = Enum.to_list(1..10_000)
large_list = Enum.to_list(1..100_000)
huge_list = Enum.to_list(1..1_000_000)
map_fun = fn i -> i * i end

Benchee.run(
  %{
    "basic" => fn {list, workers, chunk_size} ->
      :pmap2.pmap(map_fun, list, workers, chunk_size)
    end,
    "zipper" => fn {list, workers, chunk_size} ->
      :pmap2_zipper.pmap(map_fun, list, workers, chunk_size)
    end,
    "zipper + pool" => fn {list, workers, chunk_size} ->
      :pmap2_zipper_pool.pmap(map_fun, list, workers, chunk_size)
    end,
    "v8 (spawn_link + fail + unpack)" => fn {list, workers, chunk_size} ->
      :pmap_v8_unpack.pmap(map_fun, list, workers, chunk_size)
    end,
    "v2 (flush inbox)" => fn {list, workers, chunk_size} ->
      :pmap_v2_flush_inbox.pmap(map_fun, list, workers, chunk_size)
    end,
    "v5 (pool)" => fn {list, workers, chunk_size} ->
      :pmap_v5_pool.pmap(map_fun, list, workers, chunk_size)
    end,
  },
  inputs: %{
    "Medium" => {medium_list, 10, 1000},
    "Large" => {large_list, 10, 2500},
    "Huge" => {huge_list, 60, 5000}
  },
  formatters: [
    Benchee.Formatters.Console
  ],
  save: [path: "save/pmap2.save", tag: "1"],
  warmup: 30,
  time: 5,
  memory_time: 2,
  reduction_time: 2,
  # profile_after: true mpc wallet
)
