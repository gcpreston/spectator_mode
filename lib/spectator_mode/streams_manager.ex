defmodule SpectatorMode.StreamsManager do
  @moduledoc """
  A connecting process for other stream processes. Sets up relay
  creation, supervision, registration, and cleanup.

  For the general stream API, see the `SpectatorMode.Streams` context.
  """
  use GenServer
  alias SpectatorMode.BridgeRelay

  @type bridge_id() :: String.t()

  @type t() :: %__MODULE__{
    refs: %{reference() => {:source, bridge_id()} | {:relay, bridge_id()}}
  }

  defstruct refs: Map.new()

  ## API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Tells the StreamsManager to monitor the calling process as the relay for `bridge_id`.
  """
  def start_relay_monitor(bridge_id) do
    GenServer.call(__MODULE__, {:start_monitor, :relay, bridge_id})
  end

  @doc """
  Tells the StreamsManager to monitor the calling process as the source for `bridge_id`.
  """
  def start_source_monitor(bridge_id) do
    GenServer.call(__MODULE__, {:start_monitor, :source, bridge_id})
  end

  ## Callbacks

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_monitor, kind, bridge_id}, {from_pid, _alias}, %{refs: refs} = state) do
    ref = Process.monitor(from_pid)
    {:reply, :ok, %{state | refs: Map.put(refs, ref, {kind, bridge_id})},
      {:continue, {:notify_subscribers, :relay_created, bridge_id}}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _down_pid, reason}, %{refs: refs} = state) do
    IO.puts("StreamsManager caught an exit, reason: #{inspect(reason)}")

    case Map.get(refs, ref) do
      {:source, bridge_id} ->
        # stop the relay as well
        BridgeRelay.stop(bridge_id)
        updated_refs = Map.delete(refs, ref)
        {:noreply, %{state | refs: updated_refs}}

      {:relay, bridge_id} ->
        # just let subscribers know that a relay went down, it'll come back
        updated_refs = Map.delete(refs, ref)
        {:noreply, %{state | refs: updated_refs},
          {:continue, {:notify_subscribers, :relay_destroyed, bridge_id}}}
    end
  end

  @impl true
  def handle_continue({:notify_subscribers, event, result}, state) do
    notify_subscribers(event, result)
    {:noreply, state}
  end

  ## Helpers

  defp notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      "streams:index",
      {event, result}
    )
  end
end
