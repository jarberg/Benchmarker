defmodule Benchmarker.Benchmarks.Config do
  @moduledoc """
  A saved benchmark config preset (e.g., "UE5 High 1080p").
  Mirrors the original SQLAlchemy `Config` model.
  """

  use Ash.Resource,
    domain: Benchmarker.Benchmarks,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "configs"
    repo Benchmarker.Repo
  end

  json_api do
    type "config"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
    attribute :config, :map, default: %{}, public?: true

    create_timestamp :created_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :config]
    end
  end
end
