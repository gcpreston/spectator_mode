defmodule SpectatorModeWeb.Presence do
  use Phoenix.Presence,
    otp_app: :my_app,
    pubsub_server: SpectatorMode.PubSub

  ## API
  # TODO: Implement handle_metas to notify proxy:viewers on viewer join

  def get_viewer_counts() do
    # TODO: Does this want to use streams? flat_map_reduce?
    list("viewers")
    |> Enum.map(fn {_id, presence} ->
      meta = Enum.at(presence.metas, 0)
      meta.bridge_id
    end)
    |> Enum.group_by(fn bridge_id -> bridge_id end)
    |> Enum.map(fn {k, v} -> {k, Enum.count(v)} end)
    |> Enum.into(%{})
  end

  def track_viewer(viewer_id, bridge_id) do
    track(self(), "viewers", viewer_id, %{bridge_id: bridge_id})
  end

  def subscribe(), do: Phoenix.PubSub.subscribe(SpectatorMode.PubSub, "proxy:viewers")

  ## Overwrites

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_metas(topic, %{joins: joins, leaves: leaves}, _presences, state) do
    for {viewer_id, presence} <- joins do
      meta = Enum.at(presence.metas, 0)
      viewer_data = %{viewer_id: viewer_id, bridge_id: meta.bridge_id}
      msg = {__MODULE__, {:join, viewer_data}}
      Phoenix.PubSub.local_broadcast(SpectatorMode.PubSub, "proxy:#{topic}", msg)
    end

    for {viewer_id, presence} <- leaves do
      meta = Enum.at(presence.metas, 0)
      viewer_data = %{viewer_id: viewer_id, bridge_id: meta.bridge_id}
      msg = {__MODULE__, {:leave, viewer_data}}
      Phoenix.PubSub.local_broadcast(SpectatorMode.PubSub, "proxy:#{topic}", msg)
    end

    {:ok, state}
  end
end
