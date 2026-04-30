defmodule Benchmarker.Workers.Archive do
  @moduledoc """
  Extracts uploaded benchmark archives. Mirrors the `extract_archive` helper
  from `worker/runners/generic.py`. Supports .zip, .tar.gz/.tgz, .tar.bz2,
  and "this is just a standalone executable" by copying it through.
  """

  @doc """
  Extract `archive_path` into `dest_dir`. Returns `{:ok, dest_dir}` on success.
  """
  @spec extract(Path.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def extract(archive_path, dest_dir) do
    File.mkdir_p!(dest_dir)

    cond do
      String.ends_with?(archive_path, ".zip") ->
        extract_zip(archive_path, dest_dir)

      String.ends_with?(archive_path, [".tar.gz", ".tgz"]) ->
        extract_tar(archive_path, dest_dir, [:compressed])

      String.ends_with?(archive_path, ".tar.bz2") ->
        # bzip2 isn't supported by :erl_tar — fall back to system `tar`.
        case System.cmd("tar", ["-xjf", archive_path, "-C", dest_dir]) do
          {_, 0} -> {:ok, dest_dir}
          {out, code} -> {:error, {:tar_failed, code, out}}
        end

      true ->
        # Standalone executable — copy through.
        dest = Path.join(dest_dir, Path.basename(archive_path))
        :ok = File.cp!(archive_path, dest)
        File.chmod!(dest, 0o755)
        {:ok, dest_dir}
    end
  end

  defp extract_zip(path, dest) do
    case :zip.unzip(String.to_charlist(path), [{:cwd, String.to_charlist(dest)}]) do
      {:ok, _files} -> {:ok, dest}
      {:error, reason} -> {:error, {:zip_failed, reason}}
    end
  end

  defp extract_tar(path, dest, opts) do
    case :erl_tar.extract(String.to_charlist(path), [{:cwd, String.to_charlist(dest)} | opts]) do
      :ok -> {:ok, dest}
      {:error, reason} -> {:error, {:tar_failed, reason}}
    end
  end

  @doc """
  Find the first executable file under `root`, ignoring hidden files. Returns
  the path (a string) or nil. Mirrors `_find_executable` from generic.py.
  """
  def find_first_executable(root) do
    root
    |> walk()
    |> Enum.find(fn p ->
      base = Path.basename(p)
      not String.starts_with?(base, ".") and executable?(p)
    end)
  end

  @doc """
  Walk every regular file under `root` and return their paths.
  """
  def walk(root) do
    case File.ls(root) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(root, entry)

          cond do
            File.dir?(path) -> walk(path)
            true -> [path]
          end
        end)

      _ ->
        []
    end
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mode: mode, type: :regular}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end
end
