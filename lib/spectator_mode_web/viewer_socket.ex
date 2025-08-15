defmodule SpectatorModeWeb.ViewerSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorModeWeb.Presence

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  # IDEA: Cursor tracking
  # Desired behavior: On viewer reconnect case, send missing frames

  @impl true
  def connect(%{params: %{"stream_id" => stream_id}} = state) do
    stream_id = String.to_integer(stream_id)
    join_payload = Streams.register_viewer(stream_id)

    # Send initial data to viewer after connect
    if {:ok, p} = join_payload do
      send(self(), {:after_join, p})
    end

    # Track presence
    viewer_id = Ecto.UUID.generate()
    Presence.track_viewer(viewer_id, stream_id)

    {:ok, state}
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_in({_message, _opts}, state) do
    # TODO: I think this was doing nothing. When was data being sent from the user?
    {:ok, state}
  end

  @impl true
  def handle_info({:after_join, join_payload}, state) do
    {:push, {:binary, join_payload}, state}
  end

  def handle_info({:game_data, payload}, state) do
    {:push, {:binary, payload}, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
