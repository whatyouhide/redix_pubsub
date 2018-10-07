defmodule RedixPubsub.Mixfile do
  use Mix.Project

  @version "0.5.0-dev"

  def project() do
    [
      app: :redix_pubsub,
      version: @version,
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Elixir library for using Redis Pub/Sub features (built on top of Redix)",
      name: "Redix.PubSub",
      docs: [
        main: "Redix.PubSub",
        source_ref: "v#{@version}",
        source_url: "https://github.com/whatyouhide/redix_pubsub",
        extras: ["README.md"]
      ]
    ]
  end

  def application() do
    [extra_applications: [:logger]]
  end

  defp package() do
    [
      maintainers: ["Andrea Leopardi"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/whatyouhide/redix_pubsub"}
    ]
  end

  defp deps() do
    [
      {:redix, "~> 0.8"},
      {:ex_doc, "~> 0.19", only: :dev}
    ]
  end
end
