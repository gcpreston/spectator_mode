defmodule SpectatorMode.BridgeMonitorTest do
  use ExUnit.Case, async: true

  alias SpectatorMode.BridgeMonitor
  alias SpectatorMode.Streams

  defp dummy_source do
    spawn(fn ->
      receive do
        :crash -> raise "Some error occurred!"
        :stop -> nil
      end
    end)
  end

  describe "reconnection" do
    setup do
      source_pid = dummy_source()
      bridge_id = "test_id"
      stream_ids = [123, 456]
      monitor_pid = start_supervised!({BridgeMonitor, {bridge_id, stream_ids, "test_token", source_pid}})

      on_exit(fn ->
        send(source_pid, :stop)
      end)

      %{monitor_pid: monitor_pid, source_pid: source_pid, bridge_id: bridge_id, stream_ids: stream_ids}
    end

    test "exits immediately when source quits", %{monitor_pid: monitor_pid, source_pid: source_pid, stream_ids: stream_ids} do
      Streams.subscribe()
      assert Process.alive?(monitor_pid)
      # monitor test process and trap exit because refuting Process.alive?/1 alone
      # might happen too early
      Process.monitor(monitor_pid)
      Process.exit(source_pid, {:shutdown, :bridge_quit})

      assert_receive {:livestreams_destroyed, ^stream_ids}
      assert_receive {:DOWN, _ref, :process, ^monitor_pid, {:shutdown, :bridge_quit}}
      refute Process.alive?(monitor_pid)
      refute_received {:livestreams_disconnected, ^stream_ids}
    end

    test "exits after timeout when source dies", %{monitor_pid: monitor_pid, source_pid: source_pid, stream_ids: stream_ids} do
      Streams.subscribe()
      assert Process.alive?(monitor_pid)
      send(source_pid, :crash)

      assert_receive {:livestreams_disconnected, ^stream_ids}
      assert Process.alive?(monitor_pid)

      reconnect_timeout_ms = Application.get_env(:spectator_mode, :reconnect_timeout_ms)
      Process.sleep(reconnect_timeout_ms + 20)
      assert_received {:livestreams_destroyed, ^stream_ids}
      refute Process.alive?(monitor_pid)
    end

    test "allows for reconnect when source dies", %{monitor_pid: monitor_pid, source_pid: source_pid, stream_ids: stream_ids} do
      Streams.subscribe()

      crash_and_assert_reconnect = fn {source_pid, new_source_pid} ->
        send(source_pid, :crash)
        assert_receive {:livestreams_disconnected, ^stream_ids}
        {:ok, _new_reconnect_token} = BridgeMonitor.reconnect(monitor_pid, new_source_pid)

        assert_receive {:livestreams_reconnected, ^stream_ids}
        assert Process.alive?(monitor_pid)

        {new_source_pid, dummy_source()}
      end

      # Ensure multiple crashes works
      {source_pid, dummy_source()}
      |> crash_and_assert_reconnect.()
      |> crash_and_assert_reconnect.()

      refute_received {:livestreams_destroyed, ^stream_ids}
    end

    test "does not allow reconnect if source hasn't exited", %{monitor_pid: monitor_pid} do
      {:error, :not_disconnected} = BridgeMonitor.reconnect(monitor_pid, spawn(fn -> nil end))
    end
  end
end
