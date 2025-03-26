defmodule SpectatorMode.StreamsManager do
  @moduledoc """
  A connecting process for other stream processes. Sets up relay
  creation, supervision, registration, and cleanup.

  For the general stream API, see the `SpectatorMode.Streams` context.
  """
  use GenServer

  defstruct refs: Map.new()

  ## API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Tells the StreamsManager to monitor the calling process as `bridge_id`.
  """
  def start_monitor(bridge_id) do
    GenServer.call(__MODULE__, {:start_monitor, bridge_id})
  end

  ## Callbacks

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:start_monitor, bridge_id}, {from_pid, _alias}, %{refs: refs} = state) do
    ref = Process.monitor(from_pid)
    {:reply, :ok, %{state | refs: Map.put(refs, ref, bridge_id)},
      {:continue, {:notify_subscribers, :relay_created, bridge_id}}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _down_pid, reason}, %{refs: refs} = state) do
    IO.puts("StreamsManager caught an exit, reason: #{inspect(reason)}")

    case reason do
      :normal ->
        bridge_id = Map.get(refs, ref)
        updated_refs = Map.delete(refs, ref)
        {:noreply, %{state | refs: updated_refs},
          {:continue, {:notify_subscribers, :relay_destroyed, bridge_id}}}

      _ ->
        {:noreply, state}
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
