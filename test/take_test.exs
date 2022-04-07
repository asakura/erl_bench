defmodule ErlBench.TakeTest do
  use ExUnit.Case, async: true

  @input Enum.to_list(1..10)
  @expect Enum.reverse(@input)

  test "take1/2" do
    assert {:continue, @expect, _, _} =
             :take.take1(@input, 10)
  end

  test "take10/2" do
    assert {:continue, @expect, _, _} =
             :take.take10(@input, 10)
  end
end
