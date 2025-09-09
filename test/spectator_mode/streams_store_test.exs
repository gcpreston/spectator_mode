defmodule SpectatorMode.StreamsStoreTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.StreamsStore
  alias SpectatorMode.Events

  setup do
    # Start the GenServer for testing
    start_supervised!({StreamsStore, name: StreamsStoreTest})
    :ok
  end

  describe "initialization" do
    test "starts with empty state for current node" do
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert streams == []
    end
  end

  describe "stream management" do
    test "handles stream creation events" do
      node_name = Node.self()

      # Simulate stream creation event
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: 1})
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: 2, game_start: "some dummy value"})
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: 3})


      # Give the GenServer time to process
      :timer.sleep(10)

      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert length(streams) == 3

      stream_ids_result = Enum.map(streams, & &1.stream_id) |> Enum.sort()
      assert stream_ids_result == [1, 2, 3]

      # Check that all streams are associated with the correct node
      Enum.each(streams, fn stream ->
        assert stream.node_name == node_name
        assert stream.disconnected == false

        if stream.stream_id == 2, do: assert stream.game_start == "some dummy value"
      end)
    end

    test "handles stream destruction events" do
      # Create some streams first
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: 1})
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: 2})
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: 3})
      :timer.sleep(10)

      # Verify they exist
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert length(streams) == 3

      # Destroy some streams
      send(StreamsStoreTest, %Events.LivestreamDestroyed{stream_id: 1})
      send(StreamsStoreTest, %Events.LivestreamDestroyed{stream_id: 3})
      :timer.sleep(10)

      # Verify only stream 2 remains
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert length(streams) == 1
      assert hd(streams).stream_id == 2
    end

    test "can find node for specific stream" do
      node_name = Node.self()
      stream_id = 42

      # Initially stream doesn't exist
      assert StreamsStore.get_stream_node(StreamsStoreTest, stream_id) == {:error, :not_found}

      # Create the stream
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: stream_id})
      :timer.sleep(10)

      # Now it should be found
      assert StreamsStore.get_stream_node(StreamsStoreTest, stream_id) == {:ok, node_name}
    end

    test "handles duplicate stream creation gracefully" do
      stream_id = 100

      # Create stream twice
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: stream_id})
      send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: stream_id})
      :timer.sleep(10)

      # Should only have one stream
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      stream_ids = Enum.map(streams, & &1.stream_id)
      assert stream_ids == [stream_id]
    end
  end

  describe "node management" do
    test "handles node down events" do
      fake_node = :fake_node@localhost
      stream_ids = [10, 20, 30]

      # Simulate streams on a fake node
      for stream_id <- stream_ids do
        send(StreamsStoreTest, %Events.LivestreamCreated{stream_id: stream_id, node_name: fake_node})
      end
      :timer.sleep(10)

      # Verify streams exist
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert length(streams) == 3

      # Simulate node going down
      send(StreamsStoreTest, {:nodedown, fake_node})
      :timer.sleep(10)

      # Verify streams are removed
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert streams == []
    end
  end

  describe "error handling" do
    test "ignores unknown messages" do
      # Send an unknown message
      send(StreamsStoreTest, {:unknown_message, :some_data})
      :timer.sleep(10)

      # Should still work normally
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert streams == []
    end

    test "handles empty stream lists" do
      node_name = Node.self()

      # Create and then destroy all streams
      send(StreamsStoreTest, {:livestreams_created, [1, 2], node_name})
      send(StreamsStoreTest, {:livestreams_destroyed, [1, 2], node_name})
      :timer.sleep(10)

      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert streams == []
    end
  end
end
