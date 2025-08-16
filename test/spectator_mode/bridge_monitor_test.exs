defmodule SpectatorMode.BridgeMonitorTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.BridgeMonitor
  alias SpectatorMode.Streams
  alias SpectatorMode.ReconnectTokenStore
  alias SpectatorMode.GameTracker
  alias SpectatorMode.LivestreamRegistry

  defp dummy_source do
    spawn(fn ->
      receive do
        :crash -> raise "Some error occurred!"
        {:exit, reason} -> exit(reason)
      end
    end)
  end

  setup do
    source_pid = dummy_source()
    bridge_id = "bridge_monitor_test_id"
    stream_ids = [123, 456]
    reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)
    monitor_pid = start_supervised!({BridgeMonitor, {bridge_id, stream_ids, reconnect_token, source_pid}})

    on_exit(fn ->
      send(source_pid, {:exit, :shutdown})
    end)

    %{
      monitor_pid: monitor_pid,
      source_pid: source_pid,
      bridge_id: bridge_id,
      stream_ids: stream_ids,
      reconnect_token: reconnect_token
    }
  end

  describe "reconnection" do
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

  describe "cleanup" do
    test "on reconnect timeout, cleans up other processes", %{monitor_pid: monitor_pid, source_pid: source_pid, bridge_id: bridge_id, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      Streams.subscribe()

      for stream_id <- stream_ids do
        GameTracker.initialize_stream(stream_id)
      end

      # State assertions before exit
      assert GameTracker.list_streams() |> length() >= length(stream_ids)
      assert {:ok, ^bridge_id} = ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token)

      # Simulate source crash to trigger disconnect and start reconnect timeout
      send(source_pid, :crash)
      assert_receive {:livestreams_disconnected, ^stream_ids}

      assert_processes_cleaned(monitor_pid, stream_ids, reconnect_token, Application.get_env(:spectator_mode, :reconnect_timeout_ms) + 50)
    end

    test "on bridge quit, cleans up other processes", %{monitor_pid: monitor_pid, source_pid: source_pid, bridge_id: bridge_id, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      Streams.subscribe()

      for stream_id <- stream_ids do
        GameTracker.initialize_stream(stream_id)
      end

      # State assertions before exit
      assert GameTracker.list_streams() |> length() >= length(stream_ids)
      assert {:ok, ^bridge_id} = ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token)

      # Let process exit normally to simulate bridge quit
      send(source_pid, {:exit, {:shutdown, :bridge_quit}})

      assert_processes_cleaned(monitor_pid, stream_ids, reconnect_token, 100)

      refute_received {:livestreams_disconnected, ^stream_ids}
    end
  end

  defp assert_processes_cleaned(monitor_pid, stream_ids, reconnect_token, destroy_event_wait_time) do
    # Assert destroyed event is sent
    assert_receive {:livestreams_destroyed, ^stream_ids}, destroy_event_wait_time

    # Assert cleanup of other resources
    # StreamIDManager does not provide an API to check if a stream ID is taken or not
    assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: stream_id} -> stream_id in stream_ids end) |> Enum.empty?()
    assert ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token) == :error

    for stream_id <- stream_ids do
      assert is_nil(GenServer.whereis({:via, Registry, {LivestreamRegistry, stream_id}}))
    end

    # Assert monitor process is gone
    refute Process.alive?(monitor_pid)
  end
end
