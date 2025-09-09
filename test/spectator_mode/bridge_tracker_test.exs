defmodule SpectatorMode.BridgeTrackerTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.Streams
  alias SpectatorMode.Events
  alias SpectatorMode.BridgeTracker
  alias SpectatorMode.GameTracker

  describe "start_link/1" do
    test "does not allow multiple instances; creates a link anyways" do
      pid = GenServer.whereis(BridgeTracker)
      assert is_pid(pid)
      assert {:ok, ^pid} = BridgeTracker.start_link([])

      Process.flag(:trap_exit, true)
      Process.exit(pid, :kill)

      assert_receive {:EXIT, ^pid, _reason}
    end
  end

  describe "registration" do
    test "sends created notification" do
      Streams.subscribe()
      test_pid = self()

      spawn_source_pid(fn ->
        {bridge_id, stream_ids, reconnect_token} = BridgeTracker.register(2)
        send(test_pid, {:registered, bridge_id, stream_ids, reconnect_token})
      end)

      assert_receive {:registered, _bridge_id, stream_ids, _reconnect_token}

      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamCreated{stream_id: ^stream_id}
      end
    end
  end

  describe "disconnection" do
    setup do
      test_pid = self()

      source_pid = spawn_source_pid(fn ->
        {bridge_id, stream_ids, reconnect_token} = BridgeTracker.register(3)
        send(test_pid, {:registered, bridge_id, stream_ids, reconnect_token})
      end)

      assert_receive {:registered, bridge_id, stream_ids, reconnect_token}

      %{
        source_pid: source_pid,
        bridge_id: bridge_id,
        stream_ids: stream_ids,
        reconnect_token: reconnect_token
      }
    end

    test "sends destroyed notification when source quits", %{source_pid: source_pid, stream_ids: stream_ids} do
      Streams.subscribe()
      send(source_pid, {:exit, {:shutdown, :bridge_quit}})

      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDestroyed{stream_id: ^stream_id}
        refute_received %Events.LivestreamDisconnected{stream_id: ^stream_id}
      end
    end

    test "sends disconnected notification if souce crashes", %{source_pid: source_pid, stream_ids: stream_ids} do
      Streams.subscribe()
      send(source_pid, :crash)

      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDisconnected{stream_id: ^stream_id}
      end

      reconnect_timeout_ms = Application.get_env(:spectator_mode, :reconnect_timeout_ms)

      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDestroyed{stream_id: ^stream_id}, reconnect_timeout_ms + 20
      end
    end

    test "allows for reconnect when source dies", %{source_pid: source_pid, bridge_id: bridge_id, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      Streams.subscribe()
      test_pid = self()

      crash_and_assert_reconnect = fn {source_pid, reconnect_token} ->
        send(source_pid, :crash)
        for stream_id <- stream_ids do
          assert_receive %Events.LivestreamDisconnected{stream_id: ^stream_id}
        end

        new_source_pid = spawn_source_pid(fn ->
          {:ok, new_reconnect_token, ^bridge_id, ^stream_ids} = BridgeTracker.reconnect(reconnect_token)
          send(test_pid, {:reconnect_token, new_reconnect_token})
        end)

        for stream_id <- stream_ids do
          assert_receive %Events.LivestreamReconnected{stream_id: ^stream_id}
        end
        assert_receive {:reconnect_token, new_reconnect_token}

        {new_source_pid, new_reconnect_token}
      end

      # Ensure multiple crashes works
      {source_pid, reconnect_token}
      |> crash_and_assert_reconnect.()
      |> crash_and_assert_reconnect.()

      for stream_id <- stream_ids do
        refute_received %Events.LivestreamDestroyed{stream_id: ^stream_id}
      end
    end

    test "does not allow reconnect if source hasn't exited", %{reconnect_token: reconnect_token} do
      assert {:error, :not_disconnected} = BridgeTracker.reconnect(reconnect_token)
    end

    test "does not allow reconnect with bad token" do
      assert {:error, :unknown_reconnect_token} = BridgeTracker.reconnect("some fake token")
    end

    test "shows disconnected streams in disconnected_streams/0", %{stream_ids: stream_ids} do
      test_pid = self()

      other_source_pid = spawn_source_pid(fn ->
        {_, other_stream_ids, _} = BridgeTracker.register(2)
        send(test_pid, {:other_stream_ids, other_stream_ids})
      end)

      assert_receive {:other_stream_ids, other_stream_ids}
      Streams.subscribe()
      send(other_source_pid, :crash)
      for stream_id <- other_stream_ids do
        assert_receive %Events.LivestreamDisconnected{stream_id: ^stream_id}
      end

      disconnected_streams = BridgeTracker.disconnected_streams()

      for connected_stream_id <- stream_ids do
        refute MapSet.member?(disconnected_streams, connected_stream_id)
      end

      for disconnected_stream_id <- other_stream_ids do
        assert MapSet.member?(disconnected_streams, disconnected_stream_id)
      end
    end
  end

  describe "cleanup" do
    setup do
      test_pid = self()

      source_pid = spawn_source_pid(fn ->
        {bridge_id, stream_ids, reconnect_token} = BridgeTracker.register(2)
        send(test_pid, {:registered, bridge_id, stream_ids, reconnect_token})
      end)

      assert_receive {:registered, bridge_id, stream_ids, reconnect_token}

      # State assertions before exit
      Streams.subscribe()
      assert GameTracker.list_local_streams() |> length() >= length(stream_ids)
      assert {:error, :not_disconnected} = BridgeTracker.reconnect(reconnect_token)

      %{
        source_pid: source_pid,
        bridge_id: bridge_id,
        stream_ids: stream_ids,
        reconnect_token: reconnect_token
      }
    end

    test "on reconnect timeout, cleans up other processes", %{source_pid: source_pid, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      send(source_pid, :crash)
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDisconnected{stream_id: ^stream_id}
      end
      assert_processes_cleaned(stream_ids, reconnect_token, Application.get_env(:spectator_mode, :reconnect_timeout_ms) + 50)
    end

    test "on bridge quit, cleans up other processes", %{source_pid: source_pid, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      send(source_pid, {:exit, {:shutdown, :bridge_quit}})
      assert_processes_cleaned(stream_ids, reconnect_token, 100)
    end
  end

  ## Helpers

  defp spawn_source_pid(body) do
    source_pid = spawn(fn ->
      body.()

      receive do
        :crash -> raise "Some error occurred!"
        {:exit, reason} -> exit(reason)
      end
    end)

    on_exit(fn -> send(source_pid, {:exit, :shutdown}) end)

    source_pid
  end

  defp assert_processes_cleaned(stream_ids, reconnect_token, destroy_event_wait_time) do
    # Assert destroyed event is sent
    for stream_id <- stream_ids do
      assert_receive %Events.LivestreamDestroyed{stream_id: ^stream_id}, destroy_event_wait_time
    end

    # Assert cleanup of other resources
    assert GameTracker.list_local_streams() |> Enum.filter(fn %{stream_id: stream_id} -> stream_id in stream_ids end) |> Enum.empty?()
    assert BridgeTracker.reconnect(reconnect_token) == {:error, :unknown_reconnect_token}
  end
end
