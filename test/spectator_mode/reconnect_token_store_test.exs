defmodule SpectatorMode.ReconnectTokenStoreTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.Streams
  alias SpectatorMode.ReconnectTokenStore
  alias SpectatorMode.GameTracker
  alias SpectatorMode.PacketHandlerRegistry

  describe "registration" do
    test "spawns a PacketHandler process for each livestream; sends created notification" do
      bridge_id = "reconnect_token_store_test_id"
      stream_ids = Enum.map(1..2, fn _ -> GameTracker.initialize_stream() end)
      spawn_source_pid(fn -> ReconnectTokenStore.register(bridge_id, stream_ids) end)

      Streams.subscribe()
      assert_receive {:livestreams_created, ^stream_ids}

      for stream_id <- stream_ids do
        refute is_nil(GenServer.whereis({:via, Registry, {PacketHandlerRegistry, stream_id}}))
      end
    end
  end

  describe "disconnection" do
    setup do
      bridge_id = "reconnect_token_store_test_id"
      stream_ids = Enum.map(1..2, fn _ -> GameTracker.initialize_stream() end)
      test_pid = self()

      source_pid = spawn_source_pid(fn ->
        reconnect_token = ReconnectTokenStore.register(bridge_id, stream_ids)
        send(test_pid, {:reconnect_token, reconnect_token})
      end)

      assert_receive {:reconnect_token, reconnect_token}

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

      assert_receive {:livestreams_destroyed, ^stream_ids}
      refute_received {:livestreams_disconnected, ^stream_ids}
    end

    test "sends disconnected notification if souce crashes", %{source_pid: source_pid, stream_ids: stream_ids} do
      Streams.subscribe()
      send(source_pid, :crash)

      assert_receive {:livestreams_disconnected, ^stream_ids}
      reconnect_timeout_ms = Application.get_env(:spectator_mode, :reconnect_timeout_ms)
      assert_receive {:livestreams_destroyed, ^stream_ids}, reconnect_timeout_ms + 20
    end

    test "allows for reconnect when source dies", %{source_pid: source_pid, bridge_id: bridge_id, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      Streams.subscribe()
      test_pid = self()

      crash_and_assert_reconnect = fn {source_pid, reconnect_token} ->
        send(source_pid, :crash)
        assert_receive {:livestreams_disconnected, ^stream_ids}

        new_source_pid = spawn_source_pid(fn ->
          {:ok, new_reconnect_token, ^bridge_id, ^stream_ids} = ReconnectTokenStore.reconnect(reconnect_token)
          send(test_pid, {:reconnect_token, new_reconnect_token})
        end)

        assert_receive {:livestreams_reconnected, ^stream_ids}
        assert_receive {:reconnect_token, new_reconnect_token}

        {new_source_pid, new_reconnect_token}
      end

      # Ensure multiple crashes works
      {source_pid, reconnect_token}
      |> crash_and_assert_reconnect.()
      |> crash_and_assert_reconnect.()

      refute_received {:livestreams_destroyed, ^stream_ids}
    end

    test "does not allow reconnect if source hasn't exited", %{reconnect_token: reconnect_token} do
      assert {:error, :not_disconnected} = ReconnectTokenStore.reconnect(reconnect_token)
    end

    test "does not allow reconnect with bad token" do
      assert {:error, :unknown_reconnect_token} = ReconnectTokenStore.reconnect("some fake token")
    end

    test "shows disconnected streams in disconnected_streams/0", %{stream_ids: stream_ids} do
      other_bridge_id = "reconnect_token_store_test_id"
      other_stream_ids = Enum.map(1..2, fn _ -> GameTracker.initialize_stream() end)

      other_source_pid = spawn_source_pid(fn ->
        ReconnectTokenStore.register(other_bridge_id, other_stream_ids)
      end)

      Streams.subscribe()
      send(other_source_pid, :crash)
      assert_receive {:livestreams_disconnected, ^other_stream_ids}

      disconnected_streams = ReconnectTokenStore.disconnected_streams()

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
      bridge_id = "reconnect_token_store_test_id"
      stream_ids = Enum.map(1..2, fn _ -> GameTracker.initialize_stream() end)
      test_pid = self()

      source_pid = spawn_source_pid(fn ->
        reconnect_token = ReconnectTokenStore.register(bridge_id, stream_ids)
        send(test_pid, {:reconnect_token, reconnect_token})
      end)

      assert_receive {:reconnect_token, reconnect_token}

      # State assertions before exit
      Streams.subscribe()
      assert GameTracker.list_streams() |> length() >= length(stream_ids)
      assert {:error, :not_disconnected} = ReconnectTokenStore.reconnect(reconnect_token)

      %{
        source_pid: source_pid,
        bridge_id: bridge_id,
        stream_ids: stream_ids,
        reconnect_token: reconnect_token
      }
    end

    test "on reconnect timeout, cleans up other processes", %{source_pid: source_pid, stream_ids: stream_ids, reconnect_token: reconnect_token} do
      send(source_pid, :crash)
      assert_receive {:livestreams_disconnected, ^stream_ids}

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
    assert_receive {:livestreams_destroyed, ^stream_ids}, destroy_event_wait_time

    # Assert cleanup of other resources
    assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: stream_id} -> stream_id in stream_ids end) |> Enum.empty?()
    assert ReconnectTokenStore.reconnect(reconnect_token) == {:error, :unknown_reconnect_token}

    for stream_id <- stream_ids do
      assert is_nil(GenServer.whereis({:via, Registry, {PacketHandlerRegistry, stream_id}}))
    end
  end
end
