defmodule ErlBenchTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  describe "happy path" do
    @small_list Enum.to_list(1..10_000)
    @expected Enum.map(@small_list, &(&1 * 2))

    test "v1 (basic)" do
      assert :pmap_v1.pmap(&(&1 * 2), @small_list, 4) == @expected
    end

    test "v1 (basic) + inline" do
      assert :pmap_v1_inline.pmap(&(&1 * 2), @small_list, 4) == @expected
    end

    test "v2 (flush inbox)" do
      assert :pmap_v2_flush_inbox.pmap(&(&1 * 2), @small_list, 4) == @expected
    end

    test "v2 (flush inbox) + inline" do
      assert :pmap_v2_flush_inbox_inline.pmap(&(&1 * 2), @small_list, 4) == @expected
    end

    test "v3 (spawn link)" do
      assert :pmap_v3_spawn_link.pmap(&(&1 * 2), @small_list, 4) == @expected
    end

    test "v3 (spawn link) + inline" do
      assert :pmap_v3_spawn_link_inline.pmap(&(&1 * 2), @small_list, 4) == @expected
    end

    test "v4 (fail at first error)" do
      assert :pmap_v4_fail_at_first_error.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "v4 (fail at first error) + inline" do
      assert :pmap_v4_fail_at_first_error_inline.pmap(&(&1 * 2), @small_list, 4) ==
               {:ok, @expected}
    end

    test "v5 (pool)" do
      assert :pmap_v5_pool.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "v5 (pool) + inline" do
      assert :pmap_v5_pool_inline.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "v6 (pool + zipper)" do
      assert :pmap_v6_pool_zipper.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "v6 (pool + zipper) + inline" do
      assert :pmap_v6_pool_zipper_inline.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "v7 (spawn link + fail + zipper)" do
      assert :pmap_v7_spawn_link_fail_zipper.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end

    test "v7 (spawn link + fail + zipper) + inline" do
      assert :pmap_v7_spawn_link_fail_zipper_inline.pmap(&(&1 * 2), @small_list, 4) == {:ok, @expected}
    end
  end

  describe "unhappy path" do
    @tiny_list Enum.to_list(1..8)
    @expected_error [:timeout, :timeout, :timeout, 4, 5, 6, :timeout, :timeout]

    def gen_error(1), do: :timer.sleep(1000)
    def gen_error(x = 7), do: 1 / (x - 7)
    def gen_error(x), do: x

    test "v1 (basic)" do
      {result, _} = with_log(fn -> :pmap_v1.pmap(&gen_error/1, @tiny_list, 4, 3) end)
      assert result == @expected_error
    end

    test "v1 (basic) + inline" do
      {result, _} = with_log(fn -> :pmap_v1_inline.pmap(&gen_error/1, @tiny_list, 4, 3) end)
      assert result == @expected_error
    end

    test "v2 (flush inbox)" do
      {result, _} = with_log(fn -> :pmap_v2_flush_inbox.pmap(&gen_error/1, @tiny_list, 4, 3) end)
      assert result == @expected_error
    end

    test "v2 (flush inbox) + inline" do
      {result, _} =
        with_log(fn -> :pmap_v2_flush_inbox_inline.pmap(&gen_error/1, @tiny_list, 4, 3) end)

      assert result == @expected_error
    end

    test "v3 (spawn link)" do
      {result, _} = with_log(fn -> :pmap_v3_spawn_link.pmap(&gen_error/1, @tiny_list, 4, 3) end)
      assert result == @expected_error
    end

    test "v3 (spawn link) + inline" do
      {result, _} =
        with_log(fn -> :pmap_v3_spawn_link_inline.pmap(&gen_error/1, @tiny_list, 4, 3) end)

      assert result == @expected_error
    end

    test "v4 (fail at first error)" do
      {result, _} =
        with_log(fn -> :pmap_v4_fail_at_first_error.pmap(&gen_error/1, @tiny_list, 4, 3) end)

      assert result == :error
    end

    test "v4 (fail at first error) + inline" do
      {result, _} =
        with_log(fn -> :pmap_v4_fail_at_first_error.pmap(&gen_error/1, @tiny_list, 4, 3) end)

      assert result == :error
    end

    test "v5 (pool)" do
      {result, _} = with_log(fn -> :pmap_v5_pool.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "v5 (pool) + inline" do
      {result, _} = with_log(fn -> :pmap_v5_pool_inline.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "v6 (pool + zipper)" do
      {result, _} = with_log(fn -> :pmap_v6_pool_zipper.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "v6 (pool + zipper) + inline" do
      {result, _} = with_log(fn -> :pmap_v6_pool_zipper_inline.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "v7 (spawn link + fail + zipper)" do
      {result, _} = with_log(fn -> :pmap_v7_spawn_link_fail_zipper.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end

    test "v7 (spawn link + fail + zipper) + inline" do
      {result, _} = with_log(fn -> :pmap_v7_spawn_link_fail_zipper_inline.pmap(&gen_error/1, @tiny_list, 4, 2) end)
      assert result == :error
    end
  end
end
