defmodule SpectatorModeWeb.BridgeSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeRelay

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  @impl true
  def connect(state) do
    connect_result =
      if reconnect_token = state.params["reconnect_token"] do
        Streams.reconnect_relay(reconnect_token)
      else
        Streams.start_and_link_relay()
      end

    case connect_result do
      {:ok, relay_pid, bridge_id, reconnect_token} ->
        send(self(), :after_join)

        {:ok,
          state
          |> Map.put(:bridge_id, bridge_id)
          |> Map.put(:reconnect_token, reconnect_token)
          |> Map.put(:relay_pid, relay_pid)}

      {:error, reason} ->
        {:error, "Bridge connection failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    # Forward binary game data via the relay
    BridgeRelay.forward(state.relay_pid, payload)
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
  def terminate(_reason, _state) do
    :ok
  end
end
