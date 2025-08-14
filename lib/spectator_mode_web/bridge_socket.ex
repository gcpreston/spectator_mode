defmodule SpectatorModeWeb.BridgeSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  @impl true
  def connect(state) do
    stream_count = state.params["stream_count"] |> String.to_integer()

    connect_result =
      if reconnect_token = state.params["reconnect_token"] do
        Streams.reconnect_bridge(reconnect_token)
      else
        Streams.register_bridge(stream_count)
      end

    case connect_result do
      {:ok, bridge_id, stream_ids, reconnect_token} ->
        send(self(), :after_join)

        {:ok,
          state
          |> Map.put(:bridge_id, bridge_id)
          |> Map.put(:stream_ids, stream_ids)
          |> Map.put(:reconnect_token, reconnect_token)}

      {:error, reason} ->
        {:error, "Bridge connection failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def init(state) do
    Logger.debug("Bridge socket connected: #{inspect(self())}")
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    # Forward binary game data to the appropriate livestream
    {stream_id, _size, data} = parse_header(payload)
    Streams.forward(data, stream_id)
    {:ok, state}
  end

  def handle_in({"quit", [opcode: :text]}, state) do
    Logger.info("Bridge #{state.bridge_id} quit")
    {:stop, {:shutdown, :bridge_quit}, state}
  end

  @impl true
  def handle_info(:after_join, state) do
    # Notify the bridge of its generated id, stream ids, and reconnect token
    {
      :push,
      {:text,
       Jason.encode!(%{bridge_id: state.bridge_id, stream_ids: state.stream_ids, reconnect_token: state.reconnect_token})},
      state
    }
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  ## Helpers

  defp parse_header(<<stream_id::little-32>> <> <<size::little-32>> <> rest) do
    {stream_id, size, rest}
  end
end
