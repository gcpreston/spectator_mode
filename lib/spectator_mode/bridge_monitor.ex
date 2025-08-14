defmodule SpectatorMode.BridgeMonitor do
  use GenServer

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeSignals
  alias SpectatorMode.BridgeMonitorRegistry
  alias SpectatorMode.ReconnectTokenStore

  @enforce_keys [:bridge_id, :reconnect_token]
  defstruct bridge_id: nil,
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

  def start_link({bridge_id, reconnect_token, source_pid}) do
    GenServer.start_link(__MODULE__, {bridge_id, reconnect_token, source_pid},
      name: {:via, Registry, {SpectatorMode.BridgeMonitorRegistry, bridge_id, %BridgeMonitorRegistryValue{}}}
    )
  end

  @doc """
  Reconnect this relay to the calling process, which is expected to act as the
  bridge connection. For this function, the bridge must be in a disconnected
  state. On success, returns `:ok`, otherwise `{:error, reason}`.
  """
  @spec reconnect(GenServer.server(), pid()) ::
          {:ok, Streams.reconnect_token()} | {:error, term()}
  def reconnect(relay, source_pid) do
    GenServer.call(relay, {:reconnect, source_pid})
  end

  ## Callbacks

  @impl true
  def init({bridge_id, reconnect_token, source_pid}) do
    Logger.info("Starting monitor for bridge #{bridge_id}")
    Process.monitor(source_pid)
    {:ok, %__MODULE__{bridge_id: bridge_id, reconnect_token: reconnect_token}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    IO.inspect(reason, label: "bridge monitor got DOWN:")
    if reason in [:bridge_quit, {:shutdown, :local_closed}, :noproc] do
      Logger.info("Bridge #{state.bridge_id} terminating, reason: #{inspect(reason)}")
      BridgeSignals.notify_subscribers(state.bridge_id, :bridge_destroyed)
      ReconnectTokenStore.delete({:global, ReconnectTokenStore}, state.reconnect_token)

      {:stop, :normal, state}
    else
      update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, true) end)
      Streams.notify_subscribers(:bridge_disconnected, state.bridge_id)

      reconnect_timeout_ref =
        Process.send_after(self(), :reconnect_timeout, reconnect_timeout_ms())

      {:noreply, %{state | reconnect_timeout_ref: reconnect_timeout_ref}}
    end
  end

  def handle_info(:reconnect_timeout, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_call({:reconnect, source_pid}, _from, state) do
    if is_nil(state.reconnect_timeout_ref) do
      {:reply, {:error, :not_disconnected}, state}
    else
      Process.cancel_timer(state.reconnect_timeout_ref)
      Logger.info("Reconnecting relay #{state.bridge_id}")
      Process.link(source_pid)
      Process.flag(:trap_exit, true)

      new_reconnect_token =
        ReconnectTokenStore.register({:global, ReconnectTokenStore}, state.bridge_id)

      Streams.notify_subscribers(:bridge_reconnected, state.bridge_id)
      update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, false) end)

      {:reply, {:ok, new_reconnect_token},
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
end
