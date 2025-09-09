defmodule SpectatorMode.StreamsTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.Streams
  alias SpectatorMode.Events

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

  describe "register_bridge/2" do
    test "starts the specified number of livestreams" do
      Streams.subscribe()

      # Check that 5 stream IDs are received
      assert {:ok, _bridge_id, stream_ids, _reconnect_token} = Streams.register_bridge(5)
      assert length(stream_ids) == 5
      assert MapSet.new(stream_ids) |> MapSet.size() == 5

      # Check that PubSub notifications are received
      self_node_name = Node.self()
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamCreated{stream_id: ^stream_id, node_name: ^self_node_name, game_start: nil, disconnected: false}
      end
    end

    test "sends notification if the monitored process dies" do
      Streams.subscribe()
      test_pid = self()

      source_pid = spawn_source_pid(fn ->
        assert {:ok, bridge_id, stream_ids, reconnect_token} = Streams.register_bridge(3)
        send(test_pid, {:registered, bridge_id, stream_ids, reconnect_token})
      end)

      assert_receive {:registered, _bridge_id, stream_ids, _reconnect_token}
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamCreated{stream_id: ^stream_id}
      end

      send(source_pid, :crash)

      # First disconnected event is received
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDisconnected{stream_id: ^stream_id}
      end
      # After timeout, destroyed event is received
      reconnect_timeout_ms = Application.get_env(:spectator_mode, :reconnect_timeout_ms)
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDestroyed{stream_id: ^stream_id}, reconnect_timeout_ms + 20
      end
    end
  end

  describe "reconnect_bridge/2" do
    test "stops the livestreams from terminating" do
      Streams.subscribe()
      test_pid = self()

      # Register bridge initially
      source_pid = spawn_source_pid(fn ->
        assert {:ok, bridge_id, stream_ids, reconnect_token} = Streams.register_bridge(2)
        send(test_pid, {:registered, bridge_id, stream_ids, reconnect_token})
      end)

      # Crash bridge
      send(source_pid, :crash)
      assert_receive {:registered, bridge_id, stream_ids, reconnect_token}
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamDisconnected{stream_id: ^stream_id}
      end

      # Reconnect a new bridge process
      spawn_source_pid(fn ->
        assert {:ok, ^bridge_id, ^stream_ids, new_reconnect_token} = Streams.reconnect_bridge(reconnect_token)
        send(test_pid, {:reconnected, new_reconnect_token})
      end)

      # Reconnect assertions
      assert_receive {:reconnected, new_reconnect_token}
      assert reconnect_token != new_reconnect_token
      for stream_id <- stream_ids do
        assert_receive %Events.LivestreamReconnected{stream_id: ^stream_id}
      end
    end
  end
end
