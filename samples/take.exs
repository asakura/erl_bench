Benchee.run(
  %{
    "1. take1/2" => fn {list, chunk_size} ->
      :take.take_all(:take.take1(list, chunk_size))
    end,
    "2. take5/2" => fn {list, chunk_size} ->
      :take.take_all(:take.take5(list, chunk_size))
    end,
    "3. take10/2" => fn {list, chunk_size} ->
      :take.take_all(:take.take10(list, chunk_size))
    end
  },
  inputs: %{
    "00. 100, 10" => {Enum.to_list(1..100), 10},
    "01. 1k, 10" => {Enum.to_list(1..1_000), 10},
    "02. 1k, 100" => {Enum.to_list(1..1_000), 100},
    "03. 10k, 10" => {Enum.to_list(1..10_000), 10},
    "04. 10k, 100" => {Enum.to_list(1..10_000), 100},
    "05. 10k, 1000" => {Enum.to_list(1..10_000), 1000},
    "06. 100k, 10" => {Enum.to_list(1..100_000), 10},
    "07. 100k, 100" => {Enum.to_list(1..100_000), 100},
    "08. 100k, 1000" => {Enum.to_list(1..100_000), 1000},
    "09. 1M, 10" => {Enum.to_list(1..1_000_000), 10},
    "10. 1M, 100" => {Enum.to_list(1..1_000_000), 100},
    "11. 1M, 1000" => {Enum.to_list(1..1_000_000), 1000}
  },
  formatters: [
    Benchee.Formatters.Console
  ],
  warmup: 5,
  time: 5
)
