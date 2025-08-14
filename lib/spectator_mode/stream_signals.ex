defmodule SpectatorMode.StreamSignals do
  @moduledoc """
  PubSub functions for internal notifications for processes which must act
  upon changes to stream status.
  """

  alias SpectatorMode.Streams

  @pubsub_topic "stream_signals"

  @doc """
  Subscribe the calling process to receive all signals about the indicated stream.
  """
  @spec subscribe(Streams.bridge_id()) :: nil
  def subscribe(bridge_id) do
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, subtopic(bridge_id))
  end

  @doc """
  Subscribe the calling process to receive all signals about all streams.
  """
  @spec subscribe() :: nil
  def subscribe do
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, @pubsub_topic)
  end

  @doc """
  Notify subscribers of a specific stream that it has been destroyed.
  """
  @spec destroyed_signal(Streams.stream_id() | [Streams.stream_id()]) :: nil

  def destroyed_signal(stream_id_or_ids) do
    notify_subscribers(stream_id_or_ids, :stream_destroyed)
  end

  defp notify_subscribers(stream_ids, event) when is_list(stream_ids) do
    for stream_id <- stream_ids do
      notify_subscribers(stream_id, event)
    end
  end

  defp notify_subscribers(stream_id, event) do
    # Broadcast to subscribers of stream_id
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      subtopic(stream_id),
      {event, stream_id}
    )

    # Broadcast to subscribers of all streams
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      @pubsub_topic,
      {event, stream_id}
    )
  end

  defp subtopic(stream_id) do
    "#{@pubsub_topic}:#{stream_id}"
  end
end
