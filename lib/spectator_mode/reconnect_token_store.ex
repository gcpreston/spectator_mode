defmodule SpectatorMode.ReconnectTokenStore do
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

  ## Callbacks

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register, bridge_id}, _from, %{reconnect_tokens: reconnect_tokens} = state) do
    reconnect_token = :base64.encode(:crypto.strong_rand_bytes(@token_size))
    new_reconnect_tokens = Map.put(reconnect_tokens, reconnect_token, bridge_id)
    {:reply, reconnect_token, %{state | reconnect_tokens: new_reconnect_tokens}}
  end

  def handle_call({:fetch, reconnect_token}, _from, state) do
    {:reply, Map.fetch(state.reconnect_tokens, reconnect_token), state}
  end

  def handle_call({:delete, reconnect_token}, _from, state) do
    new_reconnect_tokens = Map.delete(state.reconnect_tokens, reconnect_token)
    {:reply, :ok, %{state | reconnect_tokens: new_reconnect_tokens}}
  end
end
