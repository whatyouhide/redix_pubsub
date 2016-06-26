defmodule RedixPubsub.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project() do
    [app: :redix_pubsub,
     version: @version,
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     package: [maintainers: ["Andrea Leopardi"],
               licenses: ["MIT"],
               links: %{"GitHub" => "https://github.com/whatyouhide/redix_pubsub"}],
     description: "Elixir library for using Redis Pub/Sub features (built on top of Redix)",
     name: "Redix.PubSub",
     docs: [main: "Redix.PubSub",
            source_ref: "v#{@version}",
            source_url: "https://github.com/whatyouhide/redix_pubsub",
            extras: ["README.md"]]]
  end

  def application() do
    [applications: [:logger, :redix]]
  end

  defp deps() do
    [{:connection, "~> 1.0"},
     {:redix, "~> 0.4.0"},
     {:earmark, ">= 0.0.0", only: :docs},
     {:ex_doc, ">= 0.0.0", only: :docs}]
  end
end
