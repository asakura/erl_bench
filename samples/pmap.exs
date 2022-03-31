small_list = Enum.to_list(1..1000)
medium_list = Enum.to_list(1..10_000)
large_list = Enum.to_list(1..100_000)
huge_list = Enum.to_list(1..1_000_000)
map_fun = fn i -> i * i end

Benchee.run(
  %{
    "v1 (basic)" => fn {list, workers, chunk_size} ->
      :pmap_v1.pmap(map_fun, list, workers, chunk_size)
    end,
    "v1 (basic) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v1_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v2 (flush inbox)" => fn {list, workers, chunk_size} ->
      :pmap_v2_flush_inbox.pmap(map_fun, list, workers, chunk_size)
    end,
    "v2 (flush inbox) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v2_flush_inbox_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v3 (spawn link)" => fn {list, workers, chunk_size} ->
      :pmap_v3_spawn_link.pmap(map_fun, list, workers, chunk_size)
    end,
    "v3 (spawn link) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v3_spawn_link_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v4 (fail at first error)" => fn {list, workers, chunk_size} ->
      :pmap_v4_fail_at_first_error.pmap(map_fun, list, workers, chunk_size)
    end,
    "v4 (fail at first error) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v4_fail_at_first_error_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v5 (pool)" => fn {list, workers, chunk_size} ->
      :pmap_v5_pool.pmap(map_fun, list, workers, chunk_size)
    end,
    "v5 (pool) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v5_pool_inline.pmap(map_fun, list, workers, chunk_size)
    end
  },
  inputs: %{
    "Small" => {small_list, 4, 100},
    "Medium" => {medium_list, 8, 1000},
    # "Large" => {large_list, 12, 2500},
    # "Huge" => {huge_list, 15, 5000}
  },
  formatters: [
    {Benchee.Formatters.HTML, file: "report.html"},
    Benchee.Formatters.Console
  ],
  save: [path: "pmap.save", tag: "1"],
  warmup: 5,
  time: 5,
  memory_time: 2,
  reduction_time: 2,
  profile_after: true
)
