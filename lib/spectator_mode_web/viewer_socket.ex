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
  def connect(%{params: %{"stream_id" => stream_id} = params} = state) do
    # TODO: This should be treated as if it can be invoked from outside the process
    # This function should check whether the request/auth is valid, and error if not
    # The process tracking calls should be done from init/1
    stream_id = String.to_integer(stream_id)
    get_full_replay = !!Map.get(params, "full_replay", false)

    case Streams.register_viewer(stream_id, get_full_replay) do
      {:ok, join_payload} ->
        # Send initial data to viewer after connect
        if {replay_binary, cursor} = join_payload do
          send(self(), {:after_join, join_payload})
        end

        # Track presence
        viewer_id = Ecto.UUID.generate()
        Presence.track_viewer(viewer_id, stream_id)

        {:ok, state}

      {:error, :stream_not_found} ->
        {:error, :stream_not_found}
    end
  end

  @impl true
  def init(state) do
    {:ok, state |> Map.put(:cursor, 0)}
  end

  @impl true
  def handle_in({_message, _opts}, state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:after_join, {replay_binary, cursor}}, state) do
    {:push, {:binary, join_payload}, %{state | cursor: cursor}}
  end

  def handle_info({:game_data, payload, cursor}, state) do
    if cursor > state.cursor do
      {:push, {:binary, payload}, %{state | cursor: cursor}}
    else
      {:ok, state}
    end
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
