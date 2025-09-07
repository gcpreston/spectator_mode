defmodule SpectatorMode.StreamsIndexStore do
  @moduledoc """
  A distributed store for information about all active streams, available
  throughout the cluster.
  """

  alias SpectatorMode.Streams
  alias SpectatorMode.Slp.Events

  @type stream_metadata() :: %{game_start: %Events.GameStart{}, disconnected: boolean()}

  @doc """
  Dump all currently registered stream IDs and their metadata.
  """
  @spec list_all_streams() :: %{Streams.stream_id() => stream_metadata()}
  def list_all_streams do
    # TODO
  end

  @doc """
  Synchronously bulk-insert stream IDs with default metadata to the store.
  If the stream ID is already present, its metadata is reset to the default.
  """
  @spec add_streams([Streams.stream_id()]) :: :ok
  def add_streams(stream_ids) when is_list(stream_ids) do
    # TODO
  end

  @doc """
  Bulk-delete stream IDs from the store. If a given stream ID is not already
  present, it is ignored.
  """
  @spec drop_streams([Streams.stream_id()]) :: :ok
  def drop_streams(stream_ids) when is_list(stream_ids) do
    # TODO
  end

  @doc """
  Change a metadata key-value pair for a stream ID.

  If the stream ID is not present, or if the key is unknown, the store is
  left unchanged.
  """
  @spec replace_stream_metadata(Streams.stream_id(), atom(), term()) :: :ok
  def replace_stream_metadata(stream_id, key, value) do
    # TODO
  end
end
