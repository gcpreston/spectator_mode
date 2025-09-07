defmodule SpectatorMode.StreamsIndexStore do
  @moduledoc """
  A distributed store for information about all active streams, available
  throughout the cluster.
  """

  alias SpectatorMode.Streams
  alias SpectatorMode.Slp.Events

  require Logger

  @type stream_metadata() :: %{stream_id: Streams.stream_id(), node_name: node(), game_start: %Events.GameStart{} | nil, disconnected: boolean()}

  @doc """
  Ensures the store is started and synched with the visible cluster.
  """
  @spec initialize_store() :: :ok
  def initialize_store do
    nodes_list = Node.list() ++ [node()]

    nodes_list
    |> setup_mnesia()
    |> create_stream_nodes_table()

    :mnesia.wait_for_tables([:sm_stream_nodes], 5000)
  end

  # https://www.joekoski.com/blog/2024/05/20/mnesia-cluster.html
  defp setup_mnesia(nodes) do
    :mnesia.create_schema([Node.self()])
    :mnesia.start()
    :mnesia.change_config(:extra_db_nodes, nodes)
    Logger.info("Mnesia configured with nodes: #{inspect(nodes)}")
    nodes
  end

  defp create_stream_nodes_table(nodes) do
    Logger.info("Creating sm_stream_nodes table on #{Node.self()}.")

    case :mnesia.create_table(:sm_stream_nodes, stream_nodes_table_opts(nodes)) do
      {:atomic, :ok} ->
        Logger.info("sm_stream_nodes table created successfully.")

      {:aborted, {:already_exists, table}} ->
        Logger.info("#{table} table already exists.")
    end

    nodes
  end

  defp stream_nodes_table_opts(nodes) do
    [
      {:attributes,
       [:stream_id, :node_name]},
      {:ram_copies, nodes},
      {:type, :set}
    ]
  end

  @doc """
  Dump all currently registered stream IDs and their metadata.
  """
  @spec list_all_streams() :: [stream_metadata()]
  def list_all_streams do
    # TODO: Figure out mnesia selecting
    {:atomic, result} = :mnesia.transaction(fn -> :mnesia.select(:sm_stream_nodes, [{:"$1", [], [:"$1"]}]) end) |> dbg()
    Enum.map(result, fn {:sm_stream_nodes, stream_id, meta} -> Map.put(meta, :stream_id, stream_id) end) |> dbg()
  end

  @doc """
  Synchronously bulk-insert stream IDs with default metadata to the store.
  If the stream ID is already present, its metadata is reset to the default.
  """
  @spec add_streams([Streams.stream_id()]) :: :ok
  def add_streams(stream_ids) when is_list(stream_ids) do
    # TODO: Error case
    {:atomic, [:ok]} = :mnesia.transaction(fn ->
      for stream_id <- stream_ids do
        :mnesia.write({:sm_stream_nodes, stream_id, default_stream_metadata()})
      end
    end)

    :ok
  end

  defp default_stream_metadata do
    %{node_name: Node.self(), game_start: nil, disconnected: false}
  end

  @doc """
  Bulk-delete stream IDs from the store. If a given stream ID is not already
  present, it is ignored.
  """
  @spec drop_streams([Streams.stream_id()]) :: :ok
  def drop_streams(stream_ids) when is_list(stream_ids) do
    # TODO: error case
    {:atomic, [:ok]} = :mnesia.transaction(fn ->
      for stream_id <- stream_ids do
        :mnesia.delete({:sm_stream_nodes, stream_id})
      end
    end)

    :ok
  end

  @doc """
  Change a metadata key-value pair for a stream ID.

  If the stream ID is not present, or if the key is unknown, the store is
  left unchanged.
  """
  @spec replace_stream_metadata(Streams.stream_id(), atom(), term()) :: :ok
  def replace_stream_metadata(stream_id, key, value) do
    # TODO: Error cases
    {:atomic, _} = :mnesia.transaction(fn ->
      [{:sm_stream_nodes, ^stream_id, stream_meta}] = :mnesia.read({:sm_stream_nodes, stream_id})
      new_stream_meta = Map.replace(stream_meta, key, value)
      :mnesia.write({:sm_stream_nodes, stream_id, new_stream_meta})
    end)
  end
end
