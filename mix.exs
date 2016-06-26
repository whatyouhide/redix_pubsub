defmodule RedixPubsub.Mixfile do
  use Mix.Project

  def project() do
    [app: :redix_pubsub,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application() do
    [applications: [:logger, :redix]]
  end

  defp deps() do
    [{:connection, "~> 1.0"},
     {:redix, github: "whatyouhide/redix"},
     {:earmark, ">= 0.0.0", only: :docs},
     {:ex_doc, ">= 0.0.0", only: :docs}]
  end
end
