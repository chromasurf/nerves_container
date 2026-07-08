defmodule NervesContainer.Volume do
  @moduledoc false
  import NervesContainer.Utils
  alias Nerves.Artifact

  # Sparse EXT4 image; only actually-used space is allocated on the host.
  @default_size "128G"

  @spec name(Nerves.Package.t()) :: String.t()
  def name(pkg) do
    "#{pkg.app}-#{id(pkg)}"
  end

  @spec platform_name(Nerves.Package.t()) :: String.t()
  def platform_name(pkg) do
    "#{name(pkg)}-platform"
  end

  @spec id(Nerves.Package.t()) :: String.t()
  def id(pkg) do
    id_file = id_file(pkg)

    if File.exists?(id_file) do
      File.read!(id_file)
    else
      create_id(pkg)
      id(pkg)
    end
  end

  defp id_file(pkg) do
    Artifact.build_path(pkg)
    |> Path.join(".container_id")
  end

  defp create_id(pkg) do
    id_file = id_file(pkg)
    id = Nerves.Utils.random_alpha_num(16)

    Path.dirname(id_file)
    |> File.mkdir_p!()

    File.write!(id_file, id)
  end

  @spec delete(String.t()) :: :ok
  def delete(volume_name) do
    shell_info("Deleting build volume #{volume_name}")
    args = ["volume", "delete", volume_name]

    case Mix.Nerves.Utils.shell("container", args) do
      {_result, 0} ->
        :ok

      {_result, _} ->
        Mix.raise("""
        Nerves container build_runner encountered an error while deleting volume #{volume_name}
        """)
    end
  end

  @spec exists?(String.t()) :: boolean()
  def exists?(volume_name) do
    # `container volume list` has no name filter, so filter here
    case System.cmd("container", ["volume", "list", "-q"], stderr_to_stdout: true) do
      {result, 0} ->
        result
        |> String.split("\n", trim: true)
        |> Enum.member?(volume_name)

      {result, _} ->
        Mix.raise("""
        Nerves container build_runner is unable to list volumes:

        #{result}

        Is the container system service running? Try `container system start`.
        """)
    end
  end

  @spec create(String.t(), String.t()) :: :noop
  def create(volume_name, size \\ @default_size) do
    shell_info("Creating build volume #{volume_name} (#{size})")

    case System.cmd("container", ["volume", "create", volume_name, "-s", size]) do
      {_, 0} ->
        :noop

      _ ->
        Mix.raise("Nerves container build_runner could not create volume #{volume_name}")
    end
  end
end
