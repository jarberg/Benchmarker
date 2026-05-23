defmodule Benchmarker.Benchmarks do
  @moduledoc """
  Ash domain for the benchmark service. Holds the `Job` and `Config` resources
  that replace the FastAPI / SQLAlchemy models from the original Python service.
  """

  use Ash.Domain, extensions: [AshJsonApi.Domain]

  resources do
    resource Benchmarker.Benchmarks.Job do
      define :create_job, action: :create
      define :submit_results, action: :submit_results
      define :update_job_status, action: :update_status
      define :list_jobs, action: :read
      define :get_job, action: :read, get_by: :id
    end

    resource Benchmarker.Benchmarks.Config do
      define :create_config, action: :create
      define :list_configs, action: :read
      define :get_config, action: :read, get_by: :id
      define :delete_config, action: :destroy
    end
  end

  json_api do
    routes do
      base_route "/jobs", Benchmarker.Benchmarks.Job do
        get :read
        index :read
        post :create
        patch :submit_results, route: "/:id/results"
      end

      base_route "/configs", Benchmarker.Benchmarks.Config do
        get :read
        index :read
        post :create
        delete :destroy
      end
    end
  end
end
