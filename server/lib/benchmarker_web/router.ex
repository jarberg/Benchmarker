defmodule BenchmarkerWeb.Router do
  use BenchmarkerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BenchmarkerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Inertia.Plug
  end

  pipeline :api do
    plug :accepts, ["json", "vnd.api+json"]
  end

  pipeline :upload do
    plug :accepts, ["json", "multipart/form-data"]
    plug :fetch_session
  end

  scope "/", BenchmarkerWeb do
    pipe_through :browser

    get "/", PageController, :index
  end

  # Multipart upload + worker callback (these don't fit JSON:API cleanly).
  scope "/api", BenchmarkerWeb do
    pipe_through :upload

    get  "/jobs",            JobController, :index
    post "/jobs",            JobController, :create
    get  "/jobs/:id",        JobController, :show
    get  "/jobs/:id/file",   JobController, :download
    post "/jobs/:id/results", JobController, :submit_results
    get  "/health",          HealthController, :show
  end

  # Ash JSON:API: read-only listing/detail for jobs and configs, plus config CRUD.
  scope "/jsonapi" do
    pipe_through :api
    forward "/", BenchmarkerWeb.AshJsonApiRouter
  end

  # Dev-only Phoenix LiveDashboard.
  if Application.compile_env(:benchmarker, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: BenchmarkerWeb.Telemetry
    end
  end
end

defmodule BenchmarkerWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Benchmarker.Benchmarks],
    json_schema: "/json_schema",
    open_api: "/open_api"
end
