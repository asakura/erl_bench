chunk_shuffle = fn list ->
  last_chunk_no = div(length(list), 10)

  chunks =
    Enum.zip(
      Enum.to_list(1..last_chunk_no),
      Enum.chunk_every(list, 10)
    )

  {chunks, last_chunk_no}
end

Benchee.run(
  %{
    "1. zipper/3" => fn {chunks, _last} ->
      :rearrange_concat.zipper(:rearrange.zipper_insert_chunks(chunks))
    end,
    "2. mapper_reduce/2" => fn {chunks, last} ->
      :rearrange_concat.mapper_reduce(:rearrange.mapper_insert_chunks(chunks), last)
    end,
    "3. mapper_keep/2" => fn {chunks, last} ->
      :rearrange_concat.mapper_keep(:rearrange.mapper_insert_chunks(chunks), last)
    end
  },
  inputs: %{
    "0. 100" => chunk_shuffle.(Enum.to_list(1..100)),
    "1. 1k" => chunk_shuffle.(Enum.to_list(1..1_000)),
    "2. 10k" => chunk_shuffle.(Enum.to_list(1..10_000)),
    "3. 100k" => chunk_shuffle.(Enum.to_list(1..100_000)),
    "4. 1M" => chunk_shuffle.(Enum.to_list(1..1_000_000))
  },
  formatters: [
    Benchee.Formatters.Console
  ],
  warmup: 5,
  time: 5,
  memory_time: 2,
  reduction_time: 2
)
