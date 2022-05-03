defmodule ErlBench.Pmap2Test do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  describe "happy path" do
    @small_list Enum.to_list(1..10_000)
    @expected Enum.map(@small_list, &(&1 * 2))

    test "basic" do
      assert :pmap2.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "zipper" do
      assert :pmap2_zipper.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "zipper + pool" do
      assert :pmap2_zipper_pool.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end
  end

  describe "unhappy path" do
    @tiny_list Enum.to_list(1..8)

    def gen_error(1), do: :timer.sleep(1000)
    def gen_error(x = 7), do: 1 / (x - 7)
    def gen_error(x), do: x

    test "basic" do
      {result, _} = with_log(fn -> :pmap2.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "zipper" do
      {result, _} = with_log(fn -> :pmap2_zipper.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "zipper + pool" do
      {result, _} = with_log(fn -> :pmap2_zipper_pool.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end
  end
end
