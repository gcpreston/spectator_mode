defmodule SpectatorMode.StreamsStore do
  @moduledoc """
  A global store for active streams across a multi-node cluster.

  This module maintains a singleton GenServer on each node that tracks all active
  streams across the entire cluster. It automatically synchronizes state by:

  - Querying all connected nodes on startup for their local streams
  - Subscribing to stream events to stay up-to-date with changes
  - Monitoring node connections to handle nodes joining/leaving the cluster

  The state is replicated on each node for fast local access while staying
  synchronized across the cluster.
  """
  use GenServer
  require Logger
  alias SpectatorMode.Streams

  @type stream_metadata :: %{
    stream_id: Streams.stream_id(),
    node_name: node(),
    game_start: term(),
    disconnected: boolean(),
    viewer_count: non_neg_integer()
  }

  defstruct streams_by_node: %{}, stream_metadata: %{}

  ## Public API

  @doc """
  Starts the global streams store GenServer.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, [], name: name)
  end

  @doc """
  Returns all active streams across the cluster.
  """
  @spec list_all_streams(GenServer.server()) :: [stream_metadata()]
  def list_all_streams(server \\ __MODULE__) do
    GenServer.call(server, :list_all_streams)
  end

  @doc """
  Returns the node hosting the specified stream.
  """
  @spec get_stream_node(GenServer.server(), Streams.stream_id()) :: {:ok, node()} | {:error, :not_found}
  def get_stream_node(server \\ __MODULE__, stream_id) do
    GenServer.call(server, {:get_stream_node, stream_id})
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(_opts) do
    # Monitor node connections to track cluster changes
    :net_kernel.monitor_nodes(true)

    # Subscribe to stream events to stay up-to-date
    SpectatorMode.Streams.subscribe()

    # Initialize state with current node
    initial_state = %__MODULE__{
      streams_by_node: %{Node.self() => []},
      stream_metadata: %{}
    }

    # Sync with all currently connected nodes
    connected_nodes = Node.list()
    Logger.info("StreamsStore initializing, syncing with nodes: #{inspect(connected_nodes)}")

    updated_state = sync_with_nodes(connected_nodes, initial_state)

    {:ok, updated_state}
  end

  @impl GenServer
  def handle_call(:list_all_streams, _from, state) do
    dbg(state)
    streams = Map.values(state.stream_metadata) |> dbg()
    {:reply, streams, state}
  end

  def handle_call({:get_stream_node, stream_id}, _from, state) do
    case Map.get(state.stream_metadata, stream_id) do
      %{node_name: node_name} -> {:reply, {:ok, node_name}, state}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info({:nodeup, node_name}, state) do
    Logger.info("Node joined cluster: #{inspect(node_name)}, syncing streams")
    updated_state = sync_with_nodes([node_name], state)
    {:noreply, updated_state}
  end

  def handle_info({:nodedown, node_name}, state) do
    Logger.info("Node left cluster: #{inspect(node_name)}, removing streams")
    updated_state = remove_node_streams(node_name, state)
    {:noreply, updated_state}
  end

  # Handle stream creation events
  def handle_info({:livestreams_created, stream_ids, node_name}, state) do
    Logger.debug("Streams created on #{node_name}: #{inspect(stream_ids)}")
    updated_state = add_streams_for_node(node_name, stream_ids, state)
    {:noreply, updated_state}
  end

  # Handle stream destruction events
  def handle_info({:livestreams_destroyed, stream_ids, node_name}, state) do
    Logger.debug("Streams destroyed on #{node_name}: #{inspect(stream_ids)}")
    updated_state = remove_streams_for_node(node_name, stream_ids, state)
    {:noreply, updated_state}
  end

  def handle_info({:livestreams_disconnected, stream_ids, _node_name}, state) do
    updated_state = update_stream_metadata(stream_ids, :disconnected, :true, state)
    {:noreply, updated_state}
  end

  def handle_info({:livestreams_reconnected, stream_ids, _node_name}, state) do
    updated_state = update_stream_metadata(stream_ids, :disconnected, :false, state)
    {:noreply, updated_state}
  end

  def handle_info({:game_update, {stream_id, maybe_event}, _node_name}, state) do
    updated_state = update_stream_metadata(stream_id, :game_start, maybe_event, state)
    {:noreply, updated_state}
  end

  # Ignore other messages
  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Private Functions

  @spec sync_with_nodes([node()], %__MODULE__{}) :: %__MODULE__{}
  defp sync_with_nodes([], state), do: state
  defp sync_with_nodes(nodes, state) do
    Logger.debug("Syncing streams from nodes: #{inspect(nodes)}")

    # Use :erpc.multicall for efficient parallel RPC calls
    results = :erpc.multicall(nodes, SpectatorMode.Streams, :list_local_streams, [])
    nodes_and_results = Enum.zip(nodes, results)

    # Process results and update state
    Enum.reduce(nodes_and_results, state, fn {node_name, result}, acc_state ->
      case result do
        {:ok, local_streams} ->
          process_node_streams(node_name, local_streams, acc_state)

        {:error, reason} ->
          Logger.warning("Failed to sync streams from #{node_name}: #{inspect(reason)}")
          acc_state

        {:throw, reason} ->
          Logger.warning("RPC threw error for #{node_name}: #{inspect(reason)}")
          acc_state

        {:exit, reason} ->
          Logger.warning("RPC exited for #{node_name}: #{inspect(reason)}")
          acc_state
      end
    end)
  end

  @spec process_node_streams(node(), [map()], %__MODULE__{}) :: %__MODULE__{}
  defp process_node_streams(node_name, local_streams, state) do
    # Extract stream IDs
    stream_ids = Enum.map(local_streams, & &1.stream_id)

    # Create metadata map with node information
    new_metadata =
      local_streams
      |> Enum.map(&Map.put(&1, :node_name, node_name))
      |> Enum.map(&Map.put_new(&1, :viewer_count, 0))
      |> Enum.into(%{}, &{&1.stream_id, &1})

    # Update state
    updated_streams_by_node = Map.put(state.streams_by_node, node_name, stream_ids)
    updated_stream_metadata = Map.merge(state.stream_metadata, new_metadata)

    # Local broadcast newly available streams
    # TODO: Considerations for node name in pubsub events
    # - feels like a "different layer, different abstraction" type of problem
    # - StreamsStore cares about this, but StreamsLive does not
    # - does it really make sense for StreamsStore to update itself based on
    #   the same events as the frontend?
    # - Would probably make sense to broadcast the whole metadata info for a
    #   newly created stream always, because that can hide the weirdness we
    #   see for key initialization in StreamsLive
    new_stream_ids = Map.keys(new_metadata)
    Streams.notify_local_subscribers(:livestreams_created, new_stream_ids)

    %{state |
      streams_by_node: updated_streams_by_node,
      stream_metadata: updated_stream_metadata
    }
  end

  @spec remove_node_streams(node(), %__MODULE__{}) :: %__MODULE__{}
  defp remove_node_streams(node_name, state) do
    # Get stream IDs for the node that's going down
    stream_ids_to_remove = Map.get(state.streams_by_node, node_name, [])

    # Remove node from streams_by_node
    updated_streams_by_node = Map.delete(state.streams_by_node, node_name)

    # Remove stream metadata for those streams
    updated_stream_metadata = Map.drop(state.stream_metadata, stream_ids_to_remove)

    # Local broadcast streams which are no longer available
    Streams.notify_local_subscribers(:livestreams_destroyed, stream_ids_to_remove)

    Logger.debug("Removed #{length(stream_ids_to_remove)} streams for node #{node_name}")

    %{state |
      streams_by_node: updated_streams_by_node,
      stream_metadata: updated_stream_metadata
    }
  end

  @spec add_streams_for_node(node(), [Streams.stream_id()], %__MODULE__{}) :: %__MODULE__{}
  defp add_streams_for_node(node_name, new_stream_ids, state) do
    # Get current streams for the node
    current_stream_ids = Map.get(state.streams_by_node, node_name, [])

    # Add new stream IDs (avoiding duplicates)
    updated_stream_ids = Enum.uniq(current_stream_ids ++ new_stream_ids)
    updated_streams_by_node = Map.put(state.streams_by_node, node_name, updated_stream_ids)

    # Create initial metadata for new streams
    new_metadata =
      new_stream_ids
      |> Enum.into(%{}, fn stream_id ->
        {stream_id, %{
          stream_id: stream_id,
          node_name: node_name,
          game_start: nil,
          disconnected: false,
          viewer_count: 0
        }}
      end)

    updated_stream_metadata = Map.merge(state.stream_metadata, new_metadata)

    %{state |
      streams_by_node: updated_streams_by_node,
      stream_metadata: updated_stream_metadata
    }
  end

  @spec remove_streams_for_node(node(), [Streams.stream_id()], %__MODULE__{}) :: %__MODULE__{}
  defp remove_streams_for_node(node_name, stream_ids_to_remove, state) do
    # Get current streams for the node
    current_stream_ids = Map.get(state.streams_by_node, node_name, [])

    # Remove specified stream IDs
    updated_stream_ids = current_stream_ids -- stream_ids_to_remove
    updated_streams_by_node = Map.put(state.streams_by_node, node_name, updated_stream_ids)

    # Remove metadata for removed streams
    updated_stream_metadata = Map.drop(state.stream_metadata, stream_ids_to_remove)

    %{state |
      streams_by_node: updated_streams_by_node,
      stream_metadata: updated_stream_metadata
    }
  end

  @spec update_stream_metadata(Streams.stream_id() | [Streams.stream_id()], atom(), term(), %__MODULE__{}) :: %__MODULE__{}

  defp update_stream_metadata(stream_ids, key, value, state) when is_list(stream_ids) do
    Enum.reduce(stream_ids, state, fn stream_id, acc_state ->
      update_stream_metadata(stream_id, key, value, acc_state)
    end)
  end

  defp update_stream_metadata(stream_id, key, value, state) do
    put_in(state.stream_metadata[stream_id][key], value)
  end
end
