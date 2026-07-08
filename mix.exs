defmodule NervesContainer.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/chromasurf/nerves_container"

  def project do
    [
      app: :nerves_container,
      version: @version,
      elixir: "~> 1.15",
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
