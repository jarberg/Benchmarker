defmodule BenchmarkerWeb.HealthController do
  use BenchmarkerWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
