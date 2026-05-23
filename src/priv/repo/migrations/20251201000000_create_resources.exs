defmodule Benchmarker.Repo.Migrations.CreateResources do
  use Ecto.Migration

  def up do
    # Extensions declared in Benchmarker.Repo.installed_extensions/0
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
    execute "CREATE EXTENSION IF NOT EXISTS \"citext\""

    # ash-functions: minimal shim used by AshPostgres for error-raising in queries.
    execute """
    CREATE OR REPLACE FUNCTION ash_raise_error(json jsonb, type text DEFAULT NULL)
    RETURNS jsonb
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'ash_error: %', json::text;
    END;
    $$
    """

    create table(:configs, primary_key: false) do
      add :id,         :uuid,   primary_key: true, default: fragment("uuid_generate_v4()")
      add :name,       :string
      add :config,     :map,    default: %{}
      add :created_at, :utc_datetime, null: false
      add :updated_at, :utc_datetime, null: false
    end

    create table(:jobs, primary_key: false) do
      add :id,         :uuid,   primary_key: true, default: fragment("uuid_generate_v4()")
      add :game_name,  :string, null: false
      add :file_path,  :string
      add :status,     :string, null: false, default: "pending"
      add :config,     :map,    default: %{}
      add :results,    :map
      add :error,      :text
      add :worker_id,  :string
      add :args,       :map
      add :log,        :text
      add :created_at, :utc_datetime, null: false
      add :updated_at, :utc_datetime, null: false
    end

    create index(:jobs, [:status])
    create index(:jobs, [:created_at])
  end

  def down do
    drop table(:jobs)
    drop table(:configs)
    execute "DROP FUNCTION IF EXISTS ash_raise_error(jsonb, text)"
  end
end
