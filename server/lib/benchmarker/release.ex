defmodule Benchmarker.Release do
  @moduledoc """
  Release tasks for use in production / Docker where Mix is not available.

  Called from rel/overlays/bin/server before the app starts:

      ./benchmarker eval "Benchmarker.Release.migrate()"

  Can also be run manually inside a running container:

      docker compose exec server /app/bin/benchmarker eval "Benchmarker.Release.migrate()"
  """

  @app :benchmarker

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    seed_file = Application.app_dir(@app, "priv/repo/seeds.exs")

    if File.exists?(seed_file) do
      Code.eval_file(seed_file)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
