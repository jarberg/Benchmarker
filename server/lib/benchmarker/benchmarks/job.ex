defmodule Benchmarker.Benchmarks.Job do
  @moduledoc """
  A benchmark job. Mirrors the original SQLAlchemy `Job` model:
  game_name, file_path, config (JSON), worker_id, status, results, error.
  """

  use Ash.Resource,
    domain: Benchmarker.Benchmarks,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "jobs"
    repo Benchmarker.Repo
  end

  json_api do
    type "job"
  end

  attributes do
    uuid_primary_key :id

    attribute :game_name, :string, allow_nil?: false, public?: true

    attribute :file_path, :string, public?: true

    attribute :status, :atom do
      constraints one_of: [:pending, :running, :completed, :failed]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :config, :map, default: %{}, public?: true
    attribute :args, {:array, :string}, default: [], public?: true
    attribute :log, :string, public?: true
    attribute :results, :map, public?: true
    attribute :error, :string, public?: true
    attribute :worker_id, :string, public?: true

    create_timestamp :created_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:game_name, :file_path, :config, :args]
    end

    update :submit_results do
      accept [:worker_id, :status, :results, :error, :log]
      require_atomic? false
    end

    update :update_status do
      accept [:status, :worker_id]
      require_atomic? false
    end
  end

  preparations do
    prepare build(sort: [created_at: :desc])
  end
end
