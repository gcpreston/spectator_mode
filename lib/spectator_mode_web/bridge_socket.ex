defmodule SpectatorModeWeb.BridgeSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorMode.StreamsManager
  alias SpectatorMode.BridgeRelay

  @impl true
  def child_spec(opts) do
    # We won't spawn any process, so let's ignore the child spec
    :ignore
  end

  @impl true
  def connect(%{params: %{"bridge_id" => bridge_id}} = state) do
    {:ok, pid} = Streams.start_relay(bridge_id)
    IO.inspect(bridge_id, label: "Started bridge relay")
    # TODO: Should this and start_relay be rolled into one function
    #   meant to be called from the eventual source?
    StreamsManager.start_source_monitor(bridge_id)

    {:ok, Map.put(state, :bridge_relay, pid)}
  end

  @impl true
  def init(state) do
    # Now we are effectively inside the process that maintains the socket.
    dbg(state)
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    BridgeRelay.forward(state.bridge_relay, payload)
    {:reply, :ok, {:binary, payload}, state}
  end

  # TODO: Handle metadata

  @impl true
  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
