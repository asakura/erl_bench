tiny_list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
big_list = Enum.to_list(1..1_000)

defmodule Unpacking do
  def take1([h1 | tail], n) when n > 0 do
    [h1 | take1(tail, n - 1)]
  end

  def take1([], _) do
    []
  end

  def take2([h1, h2 | tail], n) when n > 0 do
    [h1, h2 | take2(tail, n - 2)]
  end

  def take2(list, n) do
    take1(list, n)
  end

  def take3([h1, h2, h3 | tail], n) when n > 0 do
    [h1, h2, h3 | take3(tail, n - 3)]
  end

  def take3(list, n) do
    take1(list, n)
  end

  def take4([h1, h2, h3, h4 | tail], n) when n > 0 do
    [h1, h2, h3, h4 | take4(tail, n - 4)]
  end

  def take4(list, n) do
    take1(list, n)
  end

  def take5([h1, h2, h3, h4, h5 | tail], n) when n > 0 do
    [h1, h2, h3, h4, h5 | take5(tail, n - 5)]
  end

  def take5(list, n) do
    take1(list, n)
  end

  def take10([h1, h2, h3, h4, h5, h6, h7, h8, h9, h10 | tail], n) when n > 0 do
    [h1, h2, h3, h4, h5, h6, h7, h8, h9, h10 | take10(tail, n - 10)]
  end

  def take10(list, n) do
    take1(list, n)
  end
end

Benchee.run(
  %{
    "1. match 1 head" => fn ({list, count}) -> Unpacking.take1(list, count) end,
    "2. match 2 head" => fn ({list, count}) -> Unpacking.take2(list, count) end,
    "3. match 3 head" => fn ({list, count}) -> Unpacking.take3(list, count) end,
    "4. match 4 head" => fn ({list, count}) -> Unpacking.take4(list, count) end,
    "5. match 5 head" => fn ({list, count}) -> Unpacking.take5(list, count) end,
    "6. match 10 head" => fn ({list, count}) -> Unpacking.take10(list, count) end
  },
  inputs: %{
    "1. 10 list" => {tiny_list, 10},
    "2. 1k list" => {big_list, 1000}
  },
  formatters: [{Benchee.Formatters.Console, extended_statistics: true}],
  parallel: 1,
  warmup: 2,
  time: 10,
  reduction_time: 2
)
