medium_list = Enum.to_list(1..10_000)
large_list = Enum.to_list(1..100_000)
huge_list = Enum.to_list(1..1_000_000)
map_fun = fn i -> i * i end

Benchee.run(
  %{
    "v1 (basic) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v1_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v2 (flush inbox) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v2_flush_inbox_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v3 (spawn link) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v3_spawn_link_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v4 (fail at first error) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v4_fail_at_first_error_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v5 (pool) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v5_pool_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v6 (pool + zipper) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v6_pool_zipper_inline.pmap(map_fun, list, workers, chunk_size)
    end,
    "v7 (spawn_link + fail + zipper) + inline" => fn {list, workers, chunk_size} ->
      :pmap_v7_spawn_link_fail_zipper_inline.pmap(map_fun, list, workers, chunk_size)
    end
  },
  inputs: %{
    "Medium" => {medium_list, 10, 1000},
    "Large" => {large_list, 10, 2500},
    "Huge" => {huge_list, 10, 5000}
  },
  formatters: [
    {Benchee.Formatters.HTML, file: "reports/report_pmap_inline.html"},
    Benchee.Formatters.Console
  ],
  save: [path: "save/pmap_inline.save", tag: "1"],
  warmup: 5,
  time: 5,
  memory_time: 2,
  reduction_time: 2,
  profile_after: false
)
