defmodule SpectatorMode.StreamsStoreTest do
  use ExUnit.Case, async: false
  
  alias SpectatorMode.StreamsStore

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

    test "can get streams for specific node" do
      streams = StreamsStore.list_streams_for_node(StreamsStoreTest, Node.self())
      assert streams == []
    end
  end

  describe "stream management" do
    test "handles stream creation events" do
      node_name = Node.self()
      stream_ids = [1, 2, 3]

      # Simulate stream creation event
      send(StreamsStoreTest, {:livestreams_created, stream_ids, node_name})
      
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
        assert stream.viewer_count == 0
      end)
    end

    test "handles stream destruction events" do
      node_name = Node.self()
      
      # Create some streams first
      send(StreamsStoreTest, {:livestreams_created, [1, 2, 3], node_name})
      :timer.sleep(10)
      
      # Verify they exist
      streams = StreamsStore.list_all_streams(StreamsStoreTest)
      assert length(streams) == 3

      # Destroy some streams
      send(StreamsStoreTest, {:livestreams_destroyed, [1, 3], node_name})
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
      send(StreamsStoreTest, {:livestreams_created, [stream_id], node_name})
      :timer.sleep(10)

      # Now it should be found
      assert StreamsStore.get_stream_node(StreamsStoreTest, stream_id) == {:ok, node_name}
    end

    test "handles duplicate stream creation gracefully" do
      node_name = Node.self()
      stream_id = 100
      
      # Create stream twice
      send(StreamsStoreTest, {:livestreams_created, [stream_id], node_name})
      send(StreamsStoreTest, {:livestreams_created, [stream_id], node_name})
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
      send(StreamsStoreTest, {:livestreams_created, stream_ids, fake_node})
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

    test "lists streams for specific node correctly" do
      node1 = Node.self()
      node2 = :other_node@localhost
      
      # Create streams on different nodes
      send(StreamsStoreTest, {:livestreams_created, [1, 2], node1})
      send(StreamsStoreTest, {:livestreams_created, [3, 4], node2})
      :timer.sleep(10)

      # Check streams per node
      node1_streams = StreamsStore.list_streams_for_node(StreamsStoreTest, node1)
      node2_streams = StreamsStore.list_streams_for_node(StreamsStoreTest, node2)
      
      assert length(node1_streams) == 2
      assert length(node2_streams) == 2
      
      node1_ids = Enum.map(node1_streams, & &1.stream_id) |> Enum.sort()
      node2_ids = Enum.map(node2_streams, & &1.stream_id) |> Enum.sort()
      
      assert node1_ids == [1, 2]
      assert node2_ids == [3, 4]
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