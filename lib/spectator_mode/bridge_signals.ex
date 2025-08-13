defmodule SpectatorMode.BridgeSignals do
  @moduledoc """
  PubSub functions for internal notifications for processes which must act
  upon changes to bridge status.
  """

  @pubsub_topic "bridge_signals"

  def subscribe(bridge_id) do
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, subtopic(bridge_id))
  end

  def notify_subscribers(bridge_id, event) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      subtopic(bridge_id),
      event
    )
  end

  defp subtopic(bridge_id) do
    "#{@pubsub_topic}:#{bridge_id}"
  end
end
