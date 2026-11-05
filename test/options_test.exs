defmodule EtsSnapshotBundles.OptionsTest do
  use ExUnit.Case, async: true
  alias EtsSnapshotBundles, as: B
  alias EtsSnapshotBundles.{Index, Lease}
  import EtsSnapshotBundles.TestHelpers

  test "configuration has finite ceilings and rejects unknown or malformed options" do
    for options <- [
          [],
          %{unknown: 1},
          %{retired_limit: -1},
          %{retired_limit: 17},
          %{max_leases: 0},
          %{max_leases: 4097},
          %{max_keys: 65_537},
          %{max_payload_bytes: 16_777_217},
          %{max_keys: 1.0}
        ] do
      assert B.start_link(options) == {:error, :invalid_options}
    end

    index = index(%{max_keys: 0, max_payload_bytes: 0})
    assert {:ok, 1} = B.publish(index, [])
    assert B.publish(index, [{"", ""}]) == {:error, :too_many_keys}
  end

  test "invalid ordinary options and handles never consume admission" do
    index = index()

    for options <- [
          [],
          %{timeout: -1},
          %{timeout: 60_001},
          %{timeout: :infinity},
          %{expected_generation: 0},
          %{other: 1}
        ] do
      assert B.acquire(index, options) == {:error, :invalid_options}
    end

    assert B.publish(index, [], %{expected_generation: -1}) == {:error, :invalid_options}
    assert B.lookup(:bad, "a") == {:error, :invalid_handle}
    assert B.release(:bad) == {:error, :invalid_handle}
    assert B.inspect(:bad) == {:error, :invalid_handle}
    assert B.close(:bad) == {:error, :invalid_handle}

    bad_index = %Index{pid: :not_a_pid, instance: :bad, gate: :bad, limits: %{}}
    bad_lease = %Lease{index: :bad, ref: :bad, owner: :bad, generation: -1}
    assert B.publish(bad_index, []) == {:error, :invalid_handle}
    assert B.acquire(bad_index) == {:error, :invalid_handle}
    assert B.inspect(bad_index) == {:error, :invalid_handle}
    assert B.close(bad_index) == {:error, :invalid_handle}
    assert B.lookup(bad_lease, "a") == {:error, :invalid_handle}
    assert B.release(bad_lease) == {:error, :invalid_handle}
    assert :atomics.get(index.gate, 1) == 0
  end
end
