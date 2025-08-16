defmodule SpectatorMode.StreamsTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.Streams
  alias SpectatorMode.LivestreamRegistry

  # TODO: Clean up dummy sources
  # can create a test support genserver which is started with start_supervised

  defp dummy_source do
    spawn(fn ->
      receive do
        :crash -> raise "Some error occurred!"
      end
    end)
  end

  describe "register_bridge/2" do
    test "starts the specified number of livestreams" do
      Streams.subscribe()

      # Check that 5 stream IDs are received
      assert {:ok, _bridge_id, stream_ids, _reconnect_token} = Streams.register_bridge(5)
      assert length(stream_ids) == 5
      assert MapSet.new(stream_ids) |> MapSet.size() == 5

      # Check that there are 5 correct processes in the registry
      registry_stream_ids =
        Registry.select(
          LivestreamRegistry,
          [{{:"$1", :_, :_}, [], [:"$1"]}]
        )

      assert MapSet.new(registry_stream_ids) == MapSet.new(stream_ids)

      # Check that PubSub notifications are received
      for stream_id <- stream_ids do
        assert_receive {:livestream_created, ^stream_id}
      end
    end

    test "sends notification if the monitored process dies" do
      Streams.subscribe()
      source_pid = dummy_source()

      assert {:ok, _bridge_id, [stream_id], _reconnect_token} = Streams.register_bridge(1, source_pid)
      assert_receive {:livestream_created, ^stream_id}

      send(source_pid, :crash)

      # First disconnected event is received
      assert_receive {:livestreams_disconnected, [^stream_id]}
      # After timeout, destroyed event is received
      assert_receive {:livestreams_destroyed, [^stream_id]}, 500
    end
  end

  describe "reconnect_bridge/2" do
    test "stops the livestreams from terminating" do
      Streams.subscribe()
      source_pid = dummy_source()
      {:ok, bridge_id, stream_ids, reconnect_token} = Streams.register_bridge(2, source_pid)

      send(source_pid, :crash)
      assert_receive {:livestreams_disconnected, ^stream_ids}

      new_source_pid = dummy_source()

      assert {:ok, ^bridge_id, [], new_reconnect_token} =
               Streams.reconnect_bridge(reconnect_token, new_source_pid)

      assert reconnect_token != new_reconnect_token
      assert_receive {:livestreams_reconnected, ^stream_ids}
    end
  end
end
