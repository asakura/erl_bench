Benchee.run(
  %{
    "example fn fast" => fn ref -> :flush_2.example_fn_fast(ref, {ref}) end,
    "example fn slow" => fn ref -> :flush_2.example_fn_slow(ref, {ref}) end
  },
  inputs: %{
    "a ref" => make_ref()
  },
  warmup: 20,
  time: 20
)

Benchee.run(
  %{
    "example case fast" => fn ref -> :flush_2.example_case_fast(ref, {ref}) end,
    "example case slow" => fn ref -> :flush_2.example_case_slow(ref, {ref}) end
  },
  inputs: %{
    "a ref" => make_ref()
  },
  warmup: 20,
  time: 20
)

Benchee.run(
  %{
    "example recv fast" => fn ref ->
      send(self(), {ref})
      :flush_2.example_recv_fast(ref)
    end,
    "example recv slow" => fn ref ->
      send(self(), {ref})
      :flush_2.example_recv_slow(ref)
    end
  },
  inputs: %{
    "a ref" => make_ref()
  },
  warmup: 20,
  time: 20
)
