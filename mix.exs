defmodule EtsSnapshotBundles.MixProject do
  use Mix.Project

  def project do
    [
      app: :ets_snapshot_bundles,
      version: "0.1.0",
      elixir: ">= 1.18.0",
      start_permanent: Mix.env() == :prod,
      deps: [],
      name: "ETS Snapshot Bundles",
      description: "Bounded immutable ETS bundles with monitored reader leases",
      source_url: "https://github.com/martinlofranodeoliveira/ets-snapshot-bundles",
      homepage_url: "https://lofranotecnologia.com.br",
      package: [licenses: ["MIT"], maintainers: ["Lofrano Tecnologia"]]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
