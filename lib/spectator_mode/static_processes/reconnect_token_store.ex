defmodule SpectatorMode.ReconnectTokenStore do
  @moduledoc """
  Track issued reconnect tokens and look up their associated bridge IDs.
  """
  use GenServer

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.GameTracker

  @type reconnect_token :: String.t()

  @type t :: %__MODULE__{
          token_to_bridge_info: %{
            reconnect_token() => %{
              bridge_id: Streams.bridge_id(),
              stream_ids: [Streams.stream_id()],
              monitor_ref: reference()
            }
          },
          monitor_ref_to_reconnect_info: %{
            reference() => %{
              reconnect_token: reconnect_token(),
              reconnect_timeout_ref: reference() | nil
            }
          }
        }

  @token_size 32
  @global_name {:global, __MODULE__}

  defstruct token_to_bridge_info: Map.new(), monitor_ref_to_reconnect_info: Map.new()

  ## API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: @global_name)
  end

  # TODO: Some things I don't like:
  # - passing same bridge ID; feels like it wants to be defined out of existence
  # - same with stream ID; there, GameTracker handles it. It may be worth an extra layer of calls
  #   to not have this module know what a stream ID is

  @doc """
  Insert a bridge ID into the store. Tracks the calling process against the
  given bridge ID. Generates a reconnect token to return.
  """
  @spec register(Streams.bridge_id(), [Streams.stream_id()]) :: reconnect_token()
  def register(bridge_id, stream_ids) do
    GenServer.call(@global_name, {:register, bridge_id, stream_ids})
  end

  @doc """
  Connect the calling process to a disconnected bridge ID via a reconnect token.
  """
  @spec reconnect(reconnect_token()) ::
          {:ok, reconnect_token(), Streams.bridge_id(), [Streams.stream_id()]} | {:error, term()}
  def reconnect(reconnect_token) do
    GenServer.call(@global_name, {:reconnect, reconnect_token})
  end

  ## Callbacks

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register, bridge_id, stream_ids}, from, state) do
    {reconnect_token, new_state} = register_to_state(state, from, bridge_id, stream_ids)
    {:ok, _result} = start_supervised_packet_handlers(stream_ids)
    {:reply, reconnect_token, new_state}
  end

  def handle_call({:reconnect, reconnect_token}, from, state) do
    cond do
      is_nil(state.token_to_bridge_info[reconnect_token]) ->
        {:reply, {:error, :unknown_reconnect_token}, state}

      is_nil(state.token_to_bridge_info[reconnect_token].monitor_ref) ->
        {:reply, {:error, :not_disconnected}, state}

      true ->
        monitor_ref = state.token_to_bridge_info[reconnect_token].monitor_ref
        reconnect_timeout_ref = state.monitor_ref_to_reconnect_info[monitor_ref].reconnect_timeout_ref
        Process.cancel_timer(reconnect_timeout_ref)
        %{bridge_id: bridge_id, stream_ids: stream_ids} = state.token_to_bridge_info[reconnect_token]

        new_state = delete_token(state, reconnect_token)
        {new_reconnect_token, new_state} = register_to_state(new_state, from, bridge_id, stream_ids)

        Streams.notify_subscribers(:livestreams_reconnected, stream_ids)
        # update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, false) end)

        {:reply, {:ok, new_reconnect_token, bridge_id, stream_ids}, new_state}
    end
  end

  @impl true
    def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    Logger.debug("Monitor got DOWN for pid #{inspect(pid)}: #{inspect(reason)}")
    if reason in [{:shutdown, :bridge_quit}, {:shutdown, :local_closed}] do
      %{reconnect_token: reconnect_token} = state.monitor_ref_to_reconnect_info[ref]
      %{bridge_id: bridge_id} = state.token_to_bridge_info[reconnect_token]
      Logger.info("Bridge #{bridge_id} terminated, reason: #{inspect(reason)}")
      {:noreply, bridge_cleanup(state, ref)}
    else
      # update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, true) end)
      Streams.notify_subscribers(:livestreams_disconnected, state.stream_ids)
      reconnect_timeout_ref = Process.send_after(self(), :reconnect_timeout, reconnect_timeout_ms())
      {:noreply, %{state | reconnect_timeout_ref: reconnect_timeout_ref}}
    end
  end

  def handle_info({:bridge_disconnected, bridge_id}, state) do
    reconnect_timeout_ref =
      Process.send_after(self(), {:reconnect_timeout, bridge_id}, reconnect_timeout_ms())

    {:noreply, put_in(state.reconnect_timeout_refs, bridge_id, reconnect_timeout_ref)}
  end

  def handle_info({:reconnect_timeout, bridge_id}, state) do
    new_state = bridge_cleanup(state, bridge_id)
    {:noreply, new_state}
  end

  ## Helpers

  defp register_to_state(state, pid, bridge_id, stream_ids) do
    reconnect_token = :base64.encode(:crypto.strong_rand_bytes(@token_size))
    monitor_ref = Process.monitor(pid)

    new_token_to_bridge_info = Map.put(
      state.token_to_bridge_info,
      reconnect_token,
      %{bridge_id: bridge_id, stream_ids: stream_ids, monitor_ref: monitor_ref}
    )

    new_monitor_ref_to_reconnect_info = Map.put(
      state.monitor_ref_to_reconnect_info,
      monitor_ref,
      %{reconnect_toke: reconnect_token, reconnect_timeout_ref: nil}
    )

    {reconnect_token, %{state | token_to_bridge_info: new_token_to_bridge_info, monitor_ref_to_reconnect_info: new_monitor_ref_to_reconnect_info}}
  end

  # Run side-effects for bridge termination and remove it from state.
  defp bridge_cleanup(state, down_ref) do
    %{reconnect_token: reconnect_token} = state.monitor_ref_to_reconnect_info[down_ref]
    stream_ids = state.token_to_bridge_info[reconnect_token].stream_ids

    for stream_id <- stream_ids do
      GameTracker.delete(stream_id)
      livestream_name = {:via, Registry, {PacketHandlerRegistry, stream_id}}

      if GenServer.whereis({:via, Registry, {PacketHandlerRegistry, stream_id}}) != nil do
        GenServer.stop(livestream_name, {:shutdown, :reconnect_timeout})
      end
    end

    Streams.notify_subscribers(:livestreams_destroyed, stream_ids)

    state
    |> delete_monitor_ref(down_ref)
    |> delete_token(reconnect_token)
  end

  defp delete_monitor_ref(state, monitor_ref) do
    new_monitor_ref_to_reconnect_info = Map.delete(state.monitor_ref_to_reconnect_info, monitor_ref)
    %{state | monitor_ref_to_reconnect_info: new_monitor_ref_to_reconnect_info}
  end

  defp delete_token(state, reconnect_token) do
    new_token_to_bridge_info = Map.delete(state.token_to_bridge_info, reconnect_token)
    %{state | token_to_bridge_info: new_token_to_bridge_info}
  end

  defp start_supervised_packet_handlers(stream_count) do
    start_supervised_packet_handlers(stream_count, [])
  end

  defp start_supervised_packet_handlers([], acc) do
    Streams.notify_subscribers(:livestreams_created, Enum.map(acc, fn {stream_id, _stream_pid} -> stream_id end))
    {:ok, acc}
  end

  defp start_supervised_packet_handlers([stream_id | rest], acc) do
    if {:ok, stream_pid} = DynamicSupervisor.start_child(PacketHandlerSupervisor, {PacketHandler, stream_id}) do
      start_supervised_packet_handlers(rest, [{stream_id, stream_pid} | acc])
    else
      {:error, acc}
    end
  end

  defp reconnect_timeout_ms do
    Application.get_env(:spectator_mode, :reconnect_timeout_ms)
  end
end
