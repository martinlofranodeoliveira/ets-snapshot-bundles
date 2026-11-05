defmodule EtsSnapshotBundles.Index do
  @moduledoc "An instance-specific handle. Treat its fields as opaque."
  @enforce_keys [:pid, :instance, :gate, :limits]
  defstruct [:pid, :instance, :gate, :limits]
end
