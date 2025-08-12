defmodule SpectatorMode.BridgeMonitor do
  use GenServer, restart: :temporary
  # Temporary restart => new BridgeRelay upon bridge disconnect and reconnect.
  # This is for simplicity, this can probably be optimized in the future.

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeRegistry
  alias SpectatorMode.ReconnectTokenStore

  @enforce_keys [:bridge_id, :reconnect_token]
  defstruct bridge_id: nil,
            event_payloads: nil,
            current_game_start: nil,
            current_game_state: %{fod_platforms: %{left: nil, right: nil}},
            reconnect_token: nil,
            reconnect_timeout_ref: nil

  # :current_game_start stores the parsed GameStart event for the current game.
  # :current_game_state stores the ensemble of stateful information which may
  #   be needed to properly render the game and may change over time.
  #   Specifically, it stores the binary version of the latest event affecting
  #   each different part of the game state, if one has been received.
  # :reconnect_token tracks the current reconnect token. This is for logic
  #   management purposes, as opposed to security purposes; the token would
  #   have had to be given higher in the call stack already to find the
  #   bridge ID/pid in the first place.

  ## API

  defmodule BridgeRegistryValue do
    defstruct disconnected: false
  end

  def start_link({bridge_id, reconnect_token, source_pid}) do
    GenServer.start_link(__MODULE__, {bridge_id, reconnect_token, source_pid},
      name: {:via, Registry, {SpectatorMode.BridgeRegistry, bridge_id, %BridgeRegistryValue{}}}
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
    Logger.info("Starting bridge relay #{bridge_id}")
    Process.monitor(source_pid)
    notify_subscribers(:relay_created, bridge_id)
    {:ok, %__MODULE__{bridge_id: bridge_id, reconnect_token: reconnect_token}}
  end

  @impl true
  def terminate(reason, state) do
    # Notify subscribers on normal shutdowns. The possibility of this
    # callback not being invoked in a crash is not concerning, because
    # any such crash would invoke a restart from the supervisor.
    Logger.info("Relay #{state.bridge_id} terminating, reason: #{inspect(reason)}")
    notify_subscribers(:relay_destroyed, state.bridge_id)
    ReconnectTokenStore.delete({:global, ReconnectTokenStore}, state.reconnect_token)
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    if reason in [:bridge_quit, {:shutdown, :local_closed}] do
      {:stop, reason, state}
    else
      update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, true) end)
      notify_subscribers(:bridge_disconnected, state.bridge_id)

      reconnect_timeout_ref =
        Process.send_after(self(), :reconnect_timeout, reconnect_timeout_ms())

      {:noreply, %{state | reconnect_timeout_ref: reconnect_timeout_ref}}
    end
  end

  def handle_info(:reconnect_timeout, state) do
    {:stop, :bridge_disconnected, state}
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

      notify_subscribers(:bridge_reconnected, state.bridge_id)
      update_registry_value(state.bridge_id, fn value -> put_in(value.disconnected, false) end)

      {:reply, {:ok, new_reconnect_token},
       %{state | reconnect_timeout_ref: nil, reconnect_token: new_reconnect_token}}
    end
  end

  ## Helpers

  defp notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      Streams.index_subtopic(),
      {event, result}
    )
  end

  defp update_registry_value(bridge_id, updater) do
    Registry.update_value(BridgeRegistry, bridge_id, updater)
  end

  defp reconnect_timeout_ms do
    Application.get_env(:spectator_mode, :reconnect_timeout_ms)
  end
end
