defmodule Mix.Tasks.NervesContainer.Clean do
  @shortdoc "Stops leftover build containers and deletes the build volumes"

  @moduledoc """
  Frees the disk space held by this system's Apple-container build state.

  Finds every named volume belonging to the current app — including orphaned
  volumes from earlier builds — stops and removes any containers still
  referencing them, and deletes the volumes. Buildroot starts from scratch on
  the next build.

      mix nerves_container.clean          # lists what will be deleted, asks
      mix nerves_container.clean --yes    # no confirmation prompt

  The unpacked artifact cache and downloaded artifacts are not touched — use
  `mix nerves.clean <app>` and prune `~/.nerves/dl` for those.
  """

  use Mix.Task

  alias NervesContainer.Container
  alias NervesContainer.Volume

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [yes: :boolean], aliases: [y: :yes])

    prefix = "#{Mix.Project.config()[:app]}-"

    case Enum.filter(Volume.existing_names(), &String.starts_with?(&1, prefix)) do
      [] ->
        Mix.shell().info("No build volumes found for #{Mix.Project.config()[:app]}.")

      volumes ->
        clean(volumes, opts[:yes] == true)
    end
  end

  defp clean(volumes, skip_confirm?) do
    containers = Container.using_volumes(volumes)
    sized = Enum.map(volumes, &{&1, volume_size_mb(&1)})
    total = sized |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    Mix.shell().info("""
    This deletes the build state — Buildroot starts from scratch afterwards.

    Volumes (#{format_mb(total)} on disk):
    #{Enum.map_join(sized, "\n", fn {name, mb} -> "  #{name} (#{format_mb(mb)})" end)}
    #{describe_containers(containers)}\
    """)

    if skip_confirm? or Mix.shell().yes?("Proceed?") do
      for %{id: id, state: state} <- containers do
        if state == "running", do: Container.stop(id)
        Container.delete(id)
      end

      Enum.each(volumes, &Volume.delete/1)
      Mix.shell().info("Freed #{format_mb(total)}.")
    else
      Mix.shell().info("Aborted.")
    end
  end

  defp describe_containers([]), do: ""

  defp describe_containers(containers) do
    "\nContainers still referencing them (will be stopped/removed):\n" <>
      Enum.map_join(containers, "\n", &"  #{&1.id} (#{&1.state})") <> "\n"
  end

  # Real on-disk usage of the sparse volume image
  defp volume_size_mb(name) do
    dir = Path.expand("~/Library/Application Support/com.apple.container/volumes/#{name}")

    case System.cmd("du", ["-sm", dir], stderr_to_stdout: true) do
      {out, 0} -> out |> String.split() |> hd() |> String.to_integer()
      _ -> 0
    end
  end

  defp format_mb(mb) when mb >= 1024, do: "#{Float.round(mb / 1024, 1)} GB"
  defp format_mb(mb), do: "#{mb} MB"
end
