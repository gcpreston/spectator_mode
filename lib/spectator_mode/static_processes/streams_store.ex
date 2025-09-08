defmodule SpectatorMode.StreamsStore do
  @moduledoc """
  A global store for active stream info. This module acts as a place to ask
  the application about which streams are happening throughout the cluster,
  and on which node they are located.

  This global store is made up of a local process on each node to replicate
  the entirety of the data. It is kept up-to-date by messages broadcasted
  by the Streams context.
  """
  use GenServer
  require Logger

  defstruct node_name_to_stream_ids: %{}, stream_metadata: %{}

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_all_streams do
    GenServer.call(__MODULE__, :list_all_streams)
  end

  def get_stream_node(stream_id) do
    GenServer.call(__MODULE__, {:get_stream_node, stream_id})
  end

  @impl true
  def init(_) do
    :net_kernel.monitor_nodes(true) # TODO: Will this cause :nodeup to be received for nodes which were already connected?
    SpectatorMode.Streams.subscribe()

    initial_state = %__MODULE__{node_name_to_stream_ids: %{Node.self() => []}}
    remote_nodes = Node.list()
    new_state = sync_from_remote_nodes(remote_nodes, initial_state)

    {:ok, new_state}
  end

  defp sync_from_remote_nodes(remote_nodes, state) do
    IO.puts("Gonna do erpc multicall with remote_nodes #{inspect(remote_nodes)}")
    local_stream_results = :erpc.multicall(remote_nodes, SpectatorMode.Streams, :list_local_streams, [])
    nodes_and_streams = Enum.zip(remote_nodes, local_stream_results)

    remote_node_name_to_stream_ids =
      Enum.reduce(nodes_and_streams, %{}, fn {node_name, streams_result}, acc ->
        case streams_result do
          {:ok, local_streams} ->
            stream_ids = Enum.map(local_streams, fn stream_meta -> stream_meta.stream_id end)
            Map.put(acc, node_name, stream_ids)

          err ->
            Logger.error("Got an error result listing streams for node #{inspect(node_name)}: #{inspect(err)}")
            acc
        end
      end)

    remote_stream_metadata =
      Enum.reduce(nodes_and_streams, %{}, fn {node_name, streams_result}, acc ->
        case streams_result do
          {:ok, local_streams} ->
            local_streams_map = Enum.reduce(local_streams, %{}, fn stream_meta, local_acc ->
              stream_meta = Map.put(stream_meta, :node_name, node_name)
              Map.put(local_acc, stream_meta.stream_id, stream_meta)
            end)
            Map.merge(acc, local_streams_map)

          _ ->
            acc
        end
      end)

    new_node_name_to_stream_ids = Map.merge(state.node_name_to_stream_ids, remote_node_name_to_stream_ids)
    new_stream_metadata = Map.merge(state.stream_metadata, remote_stream_metadata)
    %{state | node_name_to_stream_ids: new_node_name_to_stream_ids, stream_metadata: new_stream_metadata}
  end

  @impl true
  def handle_info({:nodeup, node_name}, state) do
    {:noreply, sync_from_remote_nodes(node_name, state)}
  end

  def handle_info({:nodedown, node_name}, state) do
    stream_ids_to_remove = state.node_name_to_stream_ids[node_name] |> dbg()
    new_node_name_to_stream_ids = Map.delete(state.node_name_to_stream_ids, node_name)
    new_stream_metadata = Map.drop(state.stream_metadata, stream_ids_to_remove)

    {:noreply, %{state | node_name_to_stream_ids: new_node_name_to_stream_ids, stream_metadata: new_stream_metadata}}
  end

  def handle_info({:livestreams_created, stream_ids, node_name}, state) do
    # TODO: Deal with uniqueness
    new_node_stream_ids = state.node_name_to_stream_ids[node_name] ++ stream_ids
    new_node_name_to_stream_ids = Map.put(state.node_name_to_stream_ids, node_name, new_node_stream_ids)

    new_stream_metadata =
      Enum.reduce(stream_ids, state.stream_metadata, fn stream_id, acc ->
        # TODO: Unify this initial state somewhere
        # TODO: Should this process be connected to Presence? How do viewer counts work again lol
        Map.put(acc, stream_id, %{stream_id: stream_id, node_name: node_name, game_start: nil, disconnected: false, viewer_count: 0})
      end)

    {:noreply, %{state | node_name_to_stream_ids: new_node_name_to_stream_ids, stream_metadata: new_stream_metadata}}
  end

  def handle_info({:livestreams_destroyed, stream_ids, node_name}, state) do
    new_node_stream_ids = Enum.filter(state.node_name_to_stream_ids[node_name], fn stream_id -> stream_id not in stream_ids end)
    new_node_name_to_stream_ids = Map.put(state.node_name_to_stream_ids, node_name, new_node_stream_ids)

    new_stream_metadata = Map.drop(state.stream_metadata, stream_ids)

    {:noreply, %{state | node_name_to_stream_ids: new_node_name_to_stream_ids, stream_metadata: new_stream_metadata}}
  end

  # TODO: Would want finer-grained control over which events to receive in the first place
  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def handle_call(:list_all_streams, _from, state) do
    dbg(state)
    {:reply, Map.values(state.stream_metadata), state}
  end

  def handle_call({:get_stream_node, stream_id}, _from, state) do
    {:reply, state.stream_metadata[stream_id].node_name, state}
  end
end
