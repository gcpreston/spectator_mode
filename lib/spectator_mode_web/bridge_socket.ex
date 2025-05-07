defmodule SpectatorModeWeb.BridgeSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.BridgeRegistry
  alias SpectatorModeWeb.ReconnectTokenStore

  @reconnect_timeout_ms 10_000

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  @impl true
  def connect(state) do
    # Would this want to deny the connection if an invalid token is provided?
    {bridge_id, reconnect_token} =
      with {:ok, reconnect_token} <- Map.fetch(state.params, "reconnect_token"),
           {:ok, bridge_id} <- ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token) do
        new_reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)
        {bridge_id, new_reconnect_token}
      else
        _ ->
          bridge_id = Ecto.UUID.generate()
          new_reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)
          {bridge_id, new_reconnect_token}
      end

    {:ok, _pid} = Streams.start_and_link_relay(bridge_id, self())
    send(self(), :after_join)

    {:ok,
     state
     |> Map.put(:bridge_id, bridge_id)
     |> Map.put(:reconnect_token, reconnect_token)}
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    # Forward binary game data via the relay
    BridgeRelay.forward({:via, Registry, {BridgeRegistry, state.bridge_id}}, payload)
    {:ok, state}
  end

  def handle_in({"quit", [opcode: :text]}, state) do
    {:stop, :bridge_quit, state}
  end

  @impl true
  def handle_info(:after_join, state) do
    # Notify the bridge of its generated id and reconnect token
    {
      :push,
      {:text,
       Jason.encode!(%{bridge_id: state.bridge_id, reconnect_token: state.reconnect_token})},
      state
    }
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("bridge socket terminating, reason: #{inspect(reason)}")

    ReconnectTokenStore.delete_after(
      {:global, ReconnectTokenStore},
      state.reconnect_token,
      @reconnect_timeout_ms
    )

    :ok
  end
end
