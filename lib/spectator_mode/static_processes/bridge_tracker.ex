defmodule SpectatorMode.BridgeTracker do
  @moduledoc """
  Track the connection status of bridges. This process handles both normal
  exits (via cleanup) and non-normal exits (via a reconnect time window, and
  cleanup if the time window expires) of bridge processes, as well as sending
  pubsub messages to notify subscribers of bridge status changes.

  This is the process that keeps the Mnesia table mapping stream ID to node
  name up to date.
  """
  use GenServer

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.GameTracker

  @type t :: %__MODULE__{
          token_to_bridge_info: %{
            Streams.reconnect_token() => %{
              bridge_id: Streams.bridge_id(),
              stream_ids: [Streams.stream_id()],
              monitor_ref: reference()
            }
          },
          monitor_ref_to_reconnect_info: %{
            reference() => %{
              reconnect_token: Streams.reconnect_token(),
              reconnect_timeout_ref: reference() | nil
            }
          },
          disconnected_streams: MapSet.t(Streams.stream_id())
        }

  @token_size 32

  defstruct token_to_bridge_info: Map.new(),
            monitor_ref_to_reconnect_info: Map.new(),
            disconnected_streams: MapSet.new()

  ## API

  def start_link(_) do
    case GenServer.start_link(__MODULE__, [], name: __MODULE__) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Process.link(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Register a new bridge to the store. Generates a bridge ID, the specified
  number of stream IDs, and a reconnect token, and tracks the calling process
  as the source.
  """
  @spec register(pos_integer()) ::
          {Streams.bridge_id(), [Streams.stream_id()], Streams.reconnect_token()}
  def register(stream_count) do
    GenServer.call(__MODULE__, {:register, stream_count})
  end

  @doc """
  Connect the calling process to a disconnected bridge ID via a reconnect token.
  """
  @spec reconnect(Streams.reconnect_token()) ::
          {:ok, Streams.reconnect_token(), Streams.bridge_id(), [Streams.stream_id()]}
          | {:error, term()}
  def reconnect(reconnect_token) do
    GenServer.call(__MODULE__, {:reconnect, reconnect_token})
  end

  @doc """
  Get the set of stream IDs which are currently disconnected.
  """
  @spec disconnected_streams() :: MapSet.t(Streams.stream_id())
  def disconnected_streams() do
    GenServer.call(__MODULE__, :disconnected_streams)
  end

  ## Callbacks

  @impl true
  def init(_) do
    Logger.info("WHAT DOES Node.list() RETURN ON STARTUP: #{inspect(Node.list())} FOR NODE #{inspect(Node.self())}")
    :net_kernel.monitor_nodes(true)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register, stream_count}, {pid, _tag}, state) do
    bridge_id = Ecto.UUID.generate()
    stream_ids = Enum.map(1..stream_count, fn _ -> GameTracker.initialize_stream() end)

    {reconnect_token, new_state} = register_to_state(state, pid, bridge_id, stream_ids)

    # Register the current node as the location of the new livestreams
    # TODO: Error case
    {:atomic, [:ok]} = :mnesia.transaction(fn ->
      for stream_id <- stream_ids do
        :mnesia.write({:sm_stream_nodes, stream_id, node()})
      end
    end)

    Streams.notify_subscribers(:livestreams_created, stream_ids)
    {:reply, {bridge_id, stream_ids, reconnect_token}, new_state}
  end

  def handle_call({:reconnect, reconnect_token}, {pid, _tag}, state) do
    monitor_ref = get_in(state.token_to_bridge_info[reconnect_token].monitor_ref)

    reconnect_timeout_ref =
      get_in(state.monitor_ref_to_reconnect_info[monitor_ref].reconnect_timeout_ref)

    cond do
      is_nil(monitor_ref) ->
        {:reply, {:error, :unknown_reconnect_token}, state}

      is_nil(reconnect_timeout_ref) ->
        {:reply, {:error, :not_disconnected}, state}

      true ->
        Process.cancel_timer(reconnect_timeout_ref)

        %{bridge_id: bridge_id, stream_ids: stream_ids} =
          state.token_to_bridge_info[reconnect_token]

        new_state = delete_token(state, reconnect_token)

        new_disconnected_streams =
          MapSet.difference(state.disconnected_streams, MapSet.new(stream_ids))

        new_state = put_in(new_state.disconnected_streams, new_disconnected_streams)

        {new_reconnect_token, new_state} =
          register_to_state(new_state, pid, bridge_id, stream_ids)

        Streams.notify_subscribers(:livestreams_reconnected, stream_ids)

        {:reply, {:ok, new_reconnect_token, bridge_id, stream_ids}, new_state}
    end
  end

  def handle_call(:disconnected_streams, _from, state) do
    {:reply, state.disconnected_streams, state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, pid, reason}, state) do
    Logger.debug("Monitor got DOWN for pid #{inspect(pid)}: #{inspect(reason)}")
    %{reconnect_token: reconnect_token} = state.monitor_ref_to_reconnect_info[monitor_ref]
    %{bridge_id: bridge_id, stream_ids: stream_ids} = state.token_to_bridge_info[reconnect_token]

    if reason in [{:shutdown, :bridge_quit}, {:shutdown, :local_closed}] do
      Logger.info("Bridge #{bridge_id} terminated, reason: #{inspect(reason)}")
      # TODO: Would it be cleaner to separate the state cleaning logic from the side-effect cleaning logic?
      {:noreply, bridge_cleanup(state, monitor_ref)}
    else
      Streams.notify_subscribers(:livestreams_disconnected, stream_ids)

      reconnect_timeout_ref =
        Process.send_after(self(), {:reconnect_timeout, monitor_ref}, reconnect_timeout_ms())

      {:noreply, disconnect_in_state(state, monitor_ref, reconnect_timeout_ref)}
    end
  end

  def handle_info({:reconnect_timeout, monitor_ref}, state) do
    {:noreply, bridge_cleanup(state, monitor_ref)}
  end

  def handle_info({:nodeup, node_name}, state) do
    Logger.info("Got nodeup #{inspect(node_name)} from node #{inspect(node())}, starting Mnesia")

    nodes_list = Node.list() ++ [node()]

    nodes_list
    |> setup_mnesia()
    |> create_stream_nodes_table()

    :mnesia.wait_for_tables([:sm_stream_nodes], 5000)

    {:noreply, state}
  end

  def handle_info({:nodedown, node_name}, state) do
    Logger.info("Got nodedown #{inspect(node_name)} from node #{inspect(node())}")
    {:noreply, state}
  end

  ## Helpers

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

  # TODO: The state operations for this module feel like a state machine (aptly named...)
  #   There are a few atomic operations that happen to state, and the high-level functions
  #   (and callbacks) of this module apply either one or compose multiple, alongside some
  #   other functionality (sending notifications, etc).
  #   Defining these could be helpful, and it would make sense to have them as helpers right
  #   in this module, as they work on this module's %__MODULE__{} struct.

  defp register_to_state(state, pid, bridge_id, stream_ids) do
    reconnect_token = :base64.encode(:crypto.strong_rand_bytes(@token_size))
    monitor_ref = Process.monitor(pid)

    new_token_to_bridge_info =
      Map.put(
        state.token_to_bridge_info,
        reconnect_token,
        %{bridge_id: bridge_id, stream_ids: stream_ids, monitor_ref: monitor_ref}
      )

    new_monitor_ref_to_reconnect_info =
      Map.put(
        state.monitor_ref_to_reconnect_info,
        monitor_ref,
        %{reconnect_token: reconnect_token, reconnect_timeout_ref: nil}
      )

    {reconnect_token,
     %{
       state
       | token_to_bridge_info: new_token_to_bridge_info,
         monitor_ref_to_reconnect_info: new_monitor_ref_to_reconnect_info
     }}
  end

  # Run side-effects for bridge termination and remove it from state.
  defp bridge_cleanup(state, down_ref) do
    %{reconnect_token: reconnect_token} = state.monitor_ref_to_reconnect_info[down_ref]
    stream_ids = state.token_to_bridge_info[reconnect_token].stream_ids

    for stream_id <- stream_ids do
      GameTracker.delete(stream_id)
    end

    # TODO: error case
    {:atomic, [:ok]} = :mnesia.transaction(fn ->
      for stream_id <- stream_ids do
        :mnesia.delete({:sm_stream_nodes, stream_id})
      end
    end)

    Streams.notify_subscribers(:livestreams_destroyed, stream_ids)

    state
    |> delete_monitor_ref(down_ref)
    |> delete_token(reconnect_token)
  end

  defp delete_monitor_ref(state, monitor_ref) do
    new_monitor_ref_to_reconnect_info =
      Map.delete(state.monitor_ref_to_reconnect_info, monitor_ref)

    %{state | monitor_ref_to_reconnect_info: new_monitor_ref_to_reconnect_info}
  end

  defp delete_token(state, reconnect_token) do
    new_token_to_bridge_info = Map.delete(state.token_to_bridge_info, reconnect_token)
    %{state | token_to_bridge_info: new_token_to_bridge_info}
  end

  defp disconnect_in_state(state, monitor_ref, reconnect_timeout_ref) do
    new_state =
      put_in(
        state.monitor_ref_to_reconnect_info[monitor_ref].reconnect_timeout_ref,
        reconnect_timeout_ref
      )

    reconnect_token = new_state.monitor_ref_to_reconnect_info[monitor_ref].reconnect_token
    stream_ids = new_state.token_to_bridge_info[reconnect_token].stream_ids

    new_disconnected_streams =
      MapSet.union(new_state.disconnected_streams, MapSet.new(stream_ids))

    put_in(new_state.disconnected_streams, new_disconnected_streams)
  end

  defp reconnect_timeout_ms do
    Application.get_env(:spectator_mode, :reconnect_timeout_ms)
  end
end
