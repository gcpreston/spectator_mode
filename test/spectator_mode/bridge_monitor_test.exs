defmodule SpectatorMode.BridgeMonitorTest do
  use ExUnit.Case, async: true

  alias SpectatorMode.BridgeMonitor
  alias SpectatorMode.Streams

  defp dummy_source do
    spawn(fn ->
      receive do
        :crash -> raise "Some error occurred!"
      end
    end)
  end

  describe "reconnection" do
    setup do
      source_pid = dummy_source()

      bridge_id = "test_id"
      {:ok, relay_pid} = start_supervised({BridgeMonitor, {bridge_id, "test_token", source_pid}})
      %{relay_pid: relay_pid, source_pid: source_pid, bridge_id: bridge_id}
    end

    test "exits immediately when source quits", %{relay_pid: relay_pid, source_pid: source_pid, bridge_id: bridge_id} do
      Streams.subscribe()
      assert Process.alive?(relay_pid)
      # link test process and trap exit because refuting Process.alive?/1 alone
      # might happen too early
      Process.link(relay_pid)
      Process.flag(:trap_exit, true)
      Process.exit(source_pid, :remote)

      assert_receive {:bridge_destroyed, ^bridge_id}
      assert_receive {:EXIT, ^relay_pid, :remote}
      refute Process.alive?(relay_pid)
      refute_received {:bridge_disconnected, ^bridge_id}
    end

    test "exits after timeout when source dies", %{relay_pid: relay_pid, source_pid: source_pid, bridge_id: bridge_id} do
      Streams.subscribe()
      assert Process.alive?(relay_pid)
      send(source_pid, :crash)

      assert_receive {:bridge_disconnected, ^bridge_id}
      assert Process.alive?(relay_pid)

      reconnect_timeout_ms = Application.get_env(:spectator_mode, :reconnect_timeout_ms)
      Process.sleep(reconnect_timeout_ms + 20)
      assert_received {:bridge_destroyed, ^bridge_id}
      refute Process.alive?(relay_pid)
    end

    test "allows for reconnect when source dies", %{relay_pid: relay_pid, source_pid: source_pid, bridge_id: bridge_id} do
      Streams.subscribe()

      crash_and_assert_reconnect = fn {source_pid, new_source_pid} ->
        send(source_pid, :crash)
        assert_receive {:bridge_disconnected, ^bridge_id}
        {:ok, _new_reconnect_token} = BridgeMonitor.reconnect(relay_pid, new_source_pid)

        assert_receive {:bridge_reconnected, ^bridge_id}
        assert Process.alive?(relay_pid)

        {new_source_pid, dummy_source()}
      end

      # Ensure multiple crashes works
      {source_pid, dummy_source()}
      |> crash_and_assert_reconnect.()
      |> crash_and_assert_reconnect.()

      refute_received {:bridge_destroyed, ^bridge_id}
    end

    test "does not allow reconnect if source hasn't exited", %{relay_pid: relay_pid} do
      {:error, :not_disconnected} = BridgeMonitor.reconnect(relay_pid, spawn(fn -> nil end))
    end
  end
end
