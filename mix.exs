defmodule NervesContainer.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/chromasurf/nerves_container"

  def project do
    [
      app: :nerves_container,
      version: @version,
      elixir: "~> 1.15",
      # Registers this lib as a Nerves package so `nerves.precompile` compiles
      # it BEFORE any system package build needs the runner module. Without
      # this, fresh build dirs (new MIX_ENV, fresh checkout) hit
      # UndefinedFunctionError on first compile: precompile builds the system
      # before the regular deps-compile phase reaches this library.
      nerves_package: [type: :build_runner],
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:jason, "~> 1.2", runtime: false},
      {:nerves, "~> 1.14", runtime: false}
    ]
  end

  defp description do
    "Nerves build runner using Apple's container CLI instead of Docker on macOS"
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
