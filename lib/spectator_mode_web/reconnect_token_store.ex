defmodule SpectatorModeWeb.ReconnectTokenStore do
  @moduledoc """
  Track issued reconnect tokens and look up their associated bridge IDs.
  """
  use GenServer

  @type reconnect_token :: String.t()

  @type t :: %__MODULE__{
          reconnect_tokens: %{reconnect_token() => SpectatorMode.Streams.bridge_id()}
        }

  @token_size 32

  defstruct reconnect_tokens: Map.new()

  ## API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  @doc """
  Insert a bridge ID into the store. Generates a reconnect token to return.
  """
  @spec register(GenServer.server(), String.t()) :: String.t()
  def register(server, bridge_id) do
    GenServer.call(server, {:register, bridge_id})
  end

  @doc """
  Retrieve the bridge ID associated with a reconnect token, if one exists.
  """
  @spec fetch(GenServer.server(), String.t()) :: {:ok, String.t()} | :error
  def fetch(server, reconnect_token) do
    GenServer.call(server, {:fetch, reconnect_token})
  end

  @doc """
  Remove the specified reconnect token from the store.
  """
  def delete(server, reconnect_token) do
    GenServer.call(server, {:delete, reconnect_token})
  end

  @doc """
  Remove a reconnect token from the store after the specified amount of time
  in milliseconds.
  """
  @spec delete_after(GenServer.server(), String.t(), integer()) :: :ok
  def delete_after(server, reconnect_token, timeout_ms) do
    GenServer.call(server, {:delete_after, reconnect_token, timeout_ms})
  end

  ## Callbacks

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register, bridge_id}, _from, %{reconnect_tokens: reconnect_tokens} = state) do
    reconnect_token = :base64.encode(:crypto.strong_rand_bytes(@token_size))
    new_reconnect_tokens = Map.put(reconnect_tokens, reconnect_token, bridge_id) |> dbg()
    {:reply, reconnect_token, %{state | reconnect_tokens: new_reconnect_tokens}}
  end

  def handle_call({:fetch, reconnect_token}, _from, state) do
    {:reply, Map.fetch(state.reconnect_tokens, reconnect_token) |> dbg(), state}
  end

  def handle_call({:delete, reconnect_token}, _from, state) do
    {:reply, :ok, delete_token(state, reconnect_token)}
  end

  def handle_call({:delete_after, reconnect_token, timeout_ms}, _from, state) do
    Process.send_after(self(), {:delete, reconnect_token}, timeout_ms)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:delete, reconnect_token}, state) do
    {:noreply, delete_token(state, reconnect_token)}
  end

  defp delete_token(%{reconnect_tokens: reconnect_tokens} = state, reconnect_token) do
    new_reconnect_tokens = Map.delete(reconnect_tokens, reconnect_token) |> dbg()
    %{state | reconnect_tokens: new_reconnect_tokens}
  end
end
