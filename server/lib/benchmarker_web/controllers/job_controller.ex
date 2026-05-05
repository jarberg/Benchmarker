defmodule BenchmarkerWeb.JobController do
  use BenchmarkerWeb, :controller
  alias Benchmarker.Benchmarks

  @doc "List jobs, optionally filtered by status. Compatible with the Python CLI client."
  def index(conn, params) do
    status = params["status"]
    limit = String.to_integer(params["limit"] || "20")

    jobs =
      Benchmarks.list_jobs!()
      |> then(fn all ->
        all
        |> Enum.filter(fn j -> is_nil(status) or to_string(j.status) == status end)
        |> Enum.take(limit)
      end)

    json(conn, Enum.map(jobs, &serialize/1))
  end

  @doc "Fetch a single job by ID."
  def show(conn, %{"id" => id}) do
    case Benchmarks.get_job(id) do
      {:ok, job} -> json(conn, serialize(job))
      _ -> conn |> put_status(404) |> json(%{error: "job not found"})
    end
  end

  @doc """
  Multipart job submission. Mirrors the original FastAPI POST /jobs:
  game_name (form), config (JSON string), file (upload).
  """
  def create(conn, %{"game_name" => game_name, "file" => %Plug.Upload{} = upload} = params) do
    config =
      case params["config"] do
        nil ->
          %{}

        "" ->
          %{}

        s when is_binary(s) ->
          case Jason.decode(s) do
            {:ok, m} when is_map(m) -> m
            _ -> %{}
          end

        m when is_map(m) ->
          m
      end

    job_id = Ecto.UUID.generate()
    upload_dir = Application.get_env(:benchmarker, :upload_dir, "uploads")
    File.mkdir_p!(upload_dir)
    ext = Path.extname(upload.filename || "")
    dest = Path.join(upload_dir, "#{job_id}#{ext}")
    :ok = File.cp!(upload.path, dest)

    args = Map.get(config, "args", [])

    case Benchmarks.create_job(%{
           game_name: game_name,
           file_path: dest,
           config: config,
           args: args
         }) do
      {:ok, job} ->
        # Enqueue worker job (replaces RQ enqueue from the Python service).
        %{job_id: job.id}
        |> Benchmarker.Workers.RunBenchmark.new()
        |> Oban.insert()

        conn |> put_status(201) |> json(serialize(job))

      {:error, error} ->
        conn |> put_status(422) |> json(%{error: inspect(error)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "missing game_name or file"})
  end

  @doc "Stream the uploaded archive back to a worker."
  def download(conn, %{"id" => id}) do
    case Benchmarks.get_job(id) do
      {:ok, job} ->
        if File.exists?(job.file_path) do
          send_download(conn, {:file, job.file_path}, filename: Path.basename(job.file_path))
        else
          conn |> put_status(404) |> json(%{error: "file not found on disk"})
        end

      _ ->
        conn |> put_status(404) |> json(%{error: "job not found"})
    end
  end

  @doc "Worker callback: POST /jobs/:id/results."
  def submit_results(conn, %{"id" => id} = params) do
    with {:ok, job} <- Benchmarks.get_job(id),
         {:ok, updated} <-
           Benchmarks.submit_results(job, %{
             worker_id: params["worker_id"],
             status: String.to_atom(params["status"] || "failed"),
             results: params["results"],
             error: params["error"]
           }) do
      json(conn, serialize(updated))
    else
      _ -> conn |> put_status(404) |> json(%{error: "job not found"})
    end
  end

  defp serialize(j) do
    %{
      id: j.id,
      game_name: j.game_name,
      status: to_string(j.status),
      worker_id: j.worker_id,
      config: j.config || %{},
      args: j.args || [],
      results: j.results,
      log: j.log,
      error: j.error,
      created_at: j.created_at,
      updated_at: j.updated_at
    }
  end
end
