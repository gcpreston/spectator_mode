defmodule SpectatorModeWeb.ViewerSocket do
  @behaviour Phoenix.Socket.Transport

  alias SpectatorMode.Streams
  alias SpectatorModeWeb.Presence

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  # IDEA: Cursor tracking
  # Desired behavior: On viewer reconnect case, send missing frames

  @impl true
  def connect(%{params: %{"stream_id" => stream_id} = params} = state) do
    stream_id = String.to_integer(stream_id)
    get_full_replay = !!Map.get(params, "full_replay", false)

    case Streams.register_viewer(stream_id, get_full_replay) do
      {:ok, join_payload} ->
        # Send initial data to viewer after connect
        if join_payload do
          send(self(), {:after_join, join_payload})
        end

        # Track presence
        viewer_id = Ecto.UUID.generate()
        Presence.track_viewer(viewer_id, stream_id)

        {:ok, state |> Map.put(:stream_id, stream_id)}

      {:error, message} ->
        {:error, message}
    end
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_in({_message, _opts}, state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:after_join, join_payload}, state) do
    {:push, {:binary, join_payload}, state}
  end

  def handle_info({:game_data, payload}, state) do
    {:push, {:binary, payload}, state}
  end

  def handle_info({:disconnect, reason}, state) do
    {:stop, {:shutdown, reason}, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
