defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencias,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: [],
      aliases: [test: ["cmd rm -rf tmp/test_data", "test"]]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto], mod: {Emergencias.Application, []}]
  end
end
