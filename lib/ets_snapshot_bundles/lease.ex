defmodule EtsSnapshotBundles.Lease do
  @moduledoc "An opaque, process-bound snapshot lease."
  @enforce_keys [:index, :ref, :owner, :generation]
  defstruct [:index, :ref, :owner, :generation]
end
