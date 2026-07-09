# Chromasurf — Nerves Container Build Runner

> [!WARNING]
> Friendly heads-up: this is our internal Formrausch tooling and so far it has
> only ever built our own Chromasurf systems. Everything was lovingly tested on
> **macOS 15.7** and nothing else — apple/container officially wants macOS 26,
> but we're not emotionally ready for Tahoe's super-rounded corners yet. 🙂
> Fellow macOS-15 holdouts: if your containers come up without internet (ours
> did), the little network fix below sorts it out. Everyone braver than us:
> let us know how it goes!

**Chromasurf** is an industrial IoT platform built on [Elixir](https://elixir-lang.org) and [Nerves](https://nerves-project.org), developed by [Formrausch](https://formrausch.com). It provides the firmware foundation for connected HMI terminals, gateways, and sensor nodes — with automatic network clustering, over-the-air updates, real-time messaging, and full hardware abstraction built in. Designed for production use in manufacturing, process control, and industrial automation.

This repository contains `nerves_container`, a Nerves build runner that uses [Apple's `container` CLI](https://github.com/apple/container) instead of Docker to build Nerves systems on macOS. It is a faithful port of Nerves' stock `Nerves.Artifact.BuildRunners.Docker` — same build steps, same mounts, same official `ghcr.io/nerves-project/nerves_system_br` image — but each step runs in a lightweight, natively-arm64 Linux VM managed by Apple's container tooling. No Docker Desktop required.

## Using

Add the dependency and select the runner in your Nerves system's `mix.exs` — on macOS only, so all other hosts (Linux build servers, CI, Windows) keep the stock Nerves runner selection untouched:

```elixir
# mix.exs
defp nerves_package do
  [
    type: :system,
    build_runner: if(match?({:unix, :darwin}, :os.type()), do: NervesContainer.BuildRunner),
    # ...
  ]
end

defp deps do
  [
    {:nerves_container, github: "chromasurf/nerves_container", runtime: false},
    # ...
  ]
end
```

On macOS the rest of the host check happens at runtime (`NervesContainer.BuildRunner.available?/0`): Apple Silicon with the `container` CLI builds with Apple containers; Intel Macs or Macs without the CLI transparently fall back to `Docker` — the stock Nerves default on macOS anyway. Only the cheap OS check lives in `mix.exs`, because project config is evaluated before dependency code is loadable.

Then build as usual:

```bash
mix deps.get
mix compile              # full Buildroot build inside the container
mix nerves.artifact      # package the artifact (lands in ~/.nerves/dl)
mix nerves.system.shell  # interactive shell, e.g. for make menuconfig
mix nerves.clean <app>   # delete build volumes and cached artifact
```

The container system service is started automatically if it isn't running.

## Requirements

- Apple Silicon Mac
- [`container`](https://github.com/apple/container) ≥ 1.0.0 (`brew install container`; officially supported on macOS 26, known to work on macOS 15.7 — see the networking note below)
- `nerves_system_br` ≥ 1.28.0 in the system being built
- Host Erlang/OTP major version must match the target OTP of the system (standard Nerves rule — e.g. `nerves_system_br` 1.34.0 targets OTP 29)

## Resources

Each `container run` boots its own VM. Apple's defaults (4 CPUs / 1 GB RAM) are far too small for Buildroot, so this runner allocates **all host cores** and **half the host RAM (minimum 8G)** by default. The build directory lives in a sparse 128G EXT4 volume. Override via `build_runner_config`:

```elixir
build_runner_config: [
  cpus: 8,
  memory: "24G",     # or :host to allocate all host RAM (e.g. WebKit builds)
  volume_size: "256G",
  # custom image, same shape as the Docker runner's :docker key
  container: {"Containerfile", "my_system:0.1.0"}
]
```

The memory ceiling is cheap either way — Virtualization.framework only faults pages in as the VM actually uses them.

or environment variables (take precedence): `NERVES_CONTAINER_CPUS`, `NERVES_CONTAINER_MEMORY`, `NERVES_CONTAINER_VOLUME_SIZE`.

An existing `docker: {...}` key (for the stock Docker build runner) is honored as an image fallback, so cross-platform systems don't declare the same image twice — `container:` takes precedence when both are set.

## How It Works

The default build image is **`ghcr.io/nerves-project/nerves_system_br:<version>`** — the official Nerves build image, with the version taken from the system's `nerves_system_br` dependency. It is pulled automatically on first use and is multi-arch, so it runs natively as arm64 on Apple Silicon. A custom image can be configured via `build_runner_config` (see Resources above).

Like the Docker build runner, a build is four sequential container runs sharing a named volume (`<app>-<id>`, id stored at `ARTIFACT_DIR/.container_id`):

1. `create-build.sh <defconfig> /home/nerves/project`
2. `make [make_args]`
3. `make system NERVES_ARTIFACT_NAME=<name>`
4. `cp <name>.tar.gz /nerves/dl/` — the artifact reaches the host through the bind-mounted download cache

Differences from the Docker runner, all forced by apple/container semantics:

- **Platform volume**: GNU tar cannot create symlinks through apple/container's virtiofs ([apple/container#1209](https://github.com/apple/container/issues/1209)), and `create-build.sh` extracts the symlink-heavy Buildroot tarball into `/nerves/env/platform`. That path is therefore a second named volume (`<app>-<id>-platform`, EXT4); the host `nerves_system_br` sources are bind-mounted read-only at `/nerves/env/platform-src` and rsynced into the volume before each build, preserving the extracted `buildroot*` tree.
- **Volume prep**: fresh EXT4 volumes are root-owned (Apple's container does not copy the image mount point's ownership like Docker), so a root prep-run chowns both volumes to the image's `nerves` user and removes `lost+found`.
- **Explicit resources**: `--cpus`/`--memory` are always passed (see above).
- **Clean logs**: VM boot progress is suppressed (`--progress none`) to keep `build.log` readable.

## Stopping and Inspecting

Build containers are ephemeral (`--rm`) — one VM per build step, gone when the step finishes. There is nothing to stop after a build. The only long-lived piece is the container system service (apiserver + network helper via launchd), which the runner starts on demand:

```bash
container system status   # is the service running?
container system stop     # stop it — the runner restarts it when needed
```

If you hard-abort a running build (Ctrl-C on mix), the currently active build VM can linger:

```bash
container list            # shows leftover build containers
container stop <id>       # stop them
```

Disk usage lives in the named volumes (`container volume list`). To free it, run `mix nerves_container.clean` in the system project — it stops and removes leftover containers (which otherwise keep the volumes locked) and deletes all of the system's build volumes, including orphaned ones; `--yes` skips the confirmation. `mix nerves.clean <app>` additionally clears the unpacked artifact cache.

Build failures with known causes (volume held by a leftover container, disk full, no container network, service not running) print a targeted hint below the error.

## macOS 15: Containers Have No Network

On macOS 15 the network helper *assumes* the container subnet is `192.168.64.0/24` instead of asking vmnet (the `allocationOnly` code path; macOS 26 has proper infrastructure). If your Mac's shared vmnet network uses a different subnet — check `ifconfig bridge100` — containers are configured for the wrong network and have no connectivity at all.

Fix (no sudo required): point the helper at the actual subnet and recreate the default network:

```bash
container system stop
printf '[network]\nsubnet = "<bridge100-subnet>/24"\n' >> ~/.config/container/config.toml
rm -rf ~/Library/Application\ Support/com.apple.container/networks/default
container system start
```

Note: container IPs then share the subnet with any other vmnet VMs (e.g. UTM). The rotating allocator will occasionally hand a container an IP another VM holds — avoid running container builds concurrently with critical VMs on low IPs, or shut those VMs down.

## Troubleshooting

- **Build OOM-killed**: raise `memory:` (WebKit systems want 16G+). Buildroot resumes where it left off — just run `mix compile` again.
- **`Major version mismatch between host and target Erlang/OTP`**: standard Nerves check, unrelated to this runner — switch your host OTP (e.g. `mise use erlang@29 elixir@1.20-otp-29`).
- **`ERROR: Elixir/Mix is required to generate fwup.conf`**: the official build image ships Erlang but no Elixir. Generate `fwup.conf` on the host (`mix generate_fwup_conf`) and check it in, like the Chromasurf systems do.
- **Reclaim disk space / leftover VMs**: see "Stopping and Inspecting" above.

---

<img src="assets/fr_io_logo_signet_red.svg" alt="formrausch logo" height="24" align="top"> [formrausch](https://formrausch.com) /ˈfɔʁmˌʁaʊ̯ʃ/ is a creative studio uniting designers and developers to build beautiful, functional digital products.

## License

Apache-2.0
