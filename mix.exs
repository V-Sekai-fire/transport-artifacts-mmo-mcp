# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :artifacts_mmo_mcp,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description:
        "MCP server that plays ArtifactsMMO and records paired planner/API traces for taskweft",
      source_url: "https://github.com/weftspun/artifacts-mmo-mcp"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {ArtifactsMMOMCP.Application, []}
    ]
  end

  defp deps do
    [
      # Same pin as easy-diffusion-mcp: the weftspun fork's HTTP transport
      # carries a tools/call timeout and an SSE ETS race fix not yet upstream.
      {:ex_mcp, github: "weftspun/ex_mcp"},
      {:plug_cowboy, "~> 2.7"},
      {:req, "~> 0.6"},
      {:jason, "~> 1.4"}
    ]
  end
end
