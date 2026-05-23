defmodule BenchmarkerWeb.Schema do
  use Absinthe.Schema
  use AshGraphql, domains: [Benchmarker.Benchmarks]

  query do
  end

  mutation do
  end
end
