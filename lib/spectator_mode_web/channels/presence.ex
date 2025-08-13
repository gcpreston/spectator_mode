defmodule SpectatorModeWeb.Presence do
  use Phoenix.Presence,
    otp_app: :my_app,
    pubsub_server: SpectatorMode.PubSub

  ## API

  def get_viewer_counts() do
    list("viewers")
    |> Enum.reduce(%{}, fn {_id, presence}, acc ->
      meta = Enum.at(presence.metas, 0)
      Map.update(acc, meta.stream_id, 1, fn viewer_count -> viewer_count + 1 end)
    end)
  end

  def track_viewer(viewer_id, stream_id) do
    track(self(), "viewers", viewer_id, %{stream_id: stream_id})
  end

  def subscribe(), do: Phoenix.PubSub.subscribe(SpectatorMode.PubSub, "proxy:viewers")

  ## Callbacks

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_metas(topic, %{joins: joins, leaves: leaves}, _presences, state) do
    for {viewer_id, presence} <- joins do
      meta = Enum.at(presence.metas, 0)
      viewer_data = %{viewer_id: viewer_id, stream_id: meta.stream_id}
      msg = {__MODULE__, {:join, viewer_data}}
      Phoenix.PubSub.local_broadcast(SpectatorMode.PubSub, "proxy:#{topic}", msg)
    end

    for {viewer_id, presence} <- leaves do
      meta = Enum.at(presence.metas, 0)
      viewer_data = %{viewer_id: viewer_id, stream_id: meta.stream_id}
      msg = {__MODULE__, {:leave, viewer_data}}
      Phoenix.PubSub.local_broadcast(SpectatorMode.PubSub, "proxy:#{topic}", msg)
    end

    {:ok, state}
  end
end
