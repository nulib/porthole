defmodule Porthole.MixProject do
  use Mix.Project

  @url "https://github.com/mbklein/porthole"

  def project do
    [
      app: :porthole,
      version: "0.1.0",
      elixir: "~> 1.9",
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.circle": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:excoveralls, "~> 0.12.2", only: [:dev, :test]},
      {:ex_doc, "~> 0.19", only: [:dev, :docs]},
      {:credo, "~> 1.2.2", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Michael B. Klein"],
      links: %{GitHub: @url}
    ]
  end
end
