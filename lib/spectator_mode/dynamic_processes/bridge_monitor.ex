defmodule SpectatorMode.BridgeMonitor do
  use GenServer, restart: :transient

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeMonitorRegistry
  alias SpectatorMode.ReconnectTokenStore
  alias SpectatorMode.GameTracker
  alias SpectatorMode.PacketHandlerRegistry

  @enforce_keys [:bridge_id, :stream_ids, :reconnect_token]
  defstruct bridge_id: nil,
            stream_ids: nil,
            reconnect_token: nil,
            reconnect_timeout_ref: nil

  # :reconnect_token tracks the current reconnect token. This is for logic
  #   management purposes, as opposed to security purposes; the token would
  #   have had to be given higher in the call stack already to find the
  #   bridge ID/pid in the first place.

  ## API

  defmodule BridgeMonitorRegistryValue do
    defstruct disconnected: false
  end

  # TODO: Does this work if BridgeMonitor crashes after a reconnect?
  #   I'd imagine it would attempt to reconnect to the original pid, instead of
  #   its most recent one.
  #
  # IDEA
  # - Bridge crash => monitor sends out notifications, exits, and is restarted with new source pid on bridge reconnect
  # - Monitor crash => restart with same initialization params
  #   * if bridge crashed before monitor restart, Process.monitor will send a DOWN immediately and monitor will do its job
  # BUT: How does the reconnect timer work in this case? Maybe it could exit once bridge reconnects
  def start_link({bridge_id, stream_ids, reconnect_token, source_pid}) do
    GenServer.start_link(__MODULE__, {bridge_id, stream_ids, reconnect_token, source_pid},
      name: {:via, Registry, {SpectatorMode.BridgeMonitorRegistry, bridge_id, %BridgeMonitorRegistryValue{}}}
    )
  end

  @doc """
  Reconnect this relay to the calling process, which is expected to act as the
  bridge connection. For this function, the bridge must be in a disconnected
  state. On success, returns `:ok`, otherwise `{:error, reason}`.
  """
  @spec reconnect(GenServer.server(), pid()) ::
          {:ok, Streams.reconnect_token(), [Streams.stream_id()]} | {:error, term()}
  def reconnect(relay, source_pid) do
    GenServer.call(relay, {:reconnect, source_pid})
  end

  ## Callbacks

  @impl true
  def init({bridge_id, stream_ids, reconnect_token, source_pid}) do
    Logger.info("Starting monitor for bridge #{bridge_id}")
    Process.monitor(source_pid)
    {:ok, %__MODULE__{bridge_id: bridge_id, stream_ids: stream_ids, reconnect_token: reconnect_token}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.debug("Monitor got DOWN for pid #{inspect(pid)}: #{inspect(reason)}")
    if reason in [{:shutdown, :bridge_quit}, {:shutdown, :local_closed}] do
      Logger.info("Bridge #{state.bridge_id} terminated, reason: #{inspect(reason)}")
      bridge_cleanup(state.stream_ids, state.reconnect_token, reason)

      {:stop, {:shutdown, :bridge_quit}, state}
    else
      update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, true) end)
      Streams.notify_subscribers(:livestreams_disconnected, state.stream_ids)

      reconnect_timeout_ref =
        Process.send_after(self(), :reconnect_timeout, reconnect_timeout_ms())

      {:noreply, %{state | reconnect_timeout_ref: reconnect_timeout_ref}}
    end
  end

  def handle_info(:reconnect_timeout, state) do
    exit_reason = {:shutdown, :reconnect_timeout}
    bridge_cleanup(state.stream_ids, state.reconnect_token, exit_reason)
    {:stop, exit_reason, state}
  end

  @impl true
  def handle_call({:reconnect, source_pid}, _from, state) do
    if is_nil(state.reconnect_timeout_ref) do
      {:reply, {:error, :not_disconnected}, state}
    else
      Process.cancel_timer(state.reconnect_timeout_ref)
      Logger.info("Reconnecting relay #{state.bridge_id}")
      Process.monitor(source_pid)

      new_reconnect_token =
        ReconnectTokenStore.register({:global, ReconnectTokenStore}, state.bridge_id)

      Streams.notify_subscribers(:livestreams_reconnected, state.stream_ids)
      update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, false) end)

      {:reply, {:ok, new_reconnect_token, state.stream_ids},
       %{state | reconnect_timeout_ref: nil, reconnect_token: new_reconnect_token}}
    end
  end

  ## Helpers

  defp update_registry_value(bridge_id, updater) do
    Registry.update_value(BridgeMonitorRegistry, bridge_id, updater)
  end

  defp reconnect_timeout_ms do
    Application.get_env(:spectator_mode, :reconnect_timeout_ms)
  end

  defp bridge_cleanup(stream_ids, reconnect_token, exit_reason) do
    for stream_id <- stream_ids do
      GameTracker.delete(stream_id)

      livestream_name = {:via, Registry, {PacketHandlerRegistry, stream_id}}

      if GenServer.whereis({:via, Registry, {PacketHandlerRegistry, stream_id}}) != nil do
        GenServer.stop(livestream_name, exit_reason)
      end
    end

    ReconnectTokenStore.delete({:global, ReconnectTokenStore}, reconnect_token)
    Streams.notify_subscribers(:livestreams_destroyed, stream_ids)
  end
end
