defmodule SpectatorMode.StreamsIndexStore do
  @moduledoc """
  A distributed store for information about all active streams, available
  throughout the cluster.
  """

  alias SpectatorMode.Streams
  alias SpectatorMode.Slp.Events

  @type stream_record() :: %{stream_id: Streams.stream_id(), game_start: %Events.GameStart{}, disconnected: boolean()}

  @doc """
  Dump all currently registered stream IDs and their metadata.
  """
  @spec list_all_streams() :: [stream_record()]
  def list_all_streams do
    # TODO
  end

  @doc """
  Bulk-insert stream IDs with default metadata to the store.

  TODO: Error cases OR behavior in edge cases
  """
  @spec add_streams([Streams.stream_id()]) :: :ok
  def add_streams(stream_ids) when is_list(stream_ids) do
    # TODO
  end

  @doc """
  Bulk-delete stream IDs from the store.

  TODO: Error cases OR behavior in edge cases
  """
  @spec remove_streams([Streams.stream_id()]) :: :ok
  def remove_streams(stream_ids) when is_list(stream_ids) do
    # TODO
  end

  @doc """
  Change a piece of stored metadata for a stream ID.

  TODO: Error cases OR behavior in edge cases
  """
  def put_stream_metadata(stream_id, key, value) do
    # TODO
  end
end
