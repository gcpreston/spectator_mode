defmodule SpectatorMode.ReconnectTokenStore do
  @moduledoc """
  Track issued reconnect tokens and look up their associated bridge IDs.
  """
  use GenServer

  alias SpectatorMode.Streams

  @type reconnect_token :: String.t()

  @type t :: %__MODULE__{
          reconnect_tokens: %{reconnect_token() => SpectatorMode.Streams.bridge_id()}
        }

  @token_size 32
  @global_name {:global, __MODULE__}

  defstruct reconnect_tokens: Map.new()

  ## API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: @global_name)
  end

  @doc """
  Insert a bridge ID into the store. Generates a reconnect token to return.
  """
  @spec register(Streams.bridge_id()) :: reconnect_token()
  def register(bridge_id) do
    GenServer.call(@global_name, {:register, bridge_id})
  end

  @doc """
  Retrieve the bridge ID associated with a reconnect token, if one exists.
  """
  @spec fetch(reconnect_token()) :: {:ok, reconnect_token()} | :error
  def fetch(reconnect_token) do
    GenServer.call(@global_name, {:fetch, reconnect_token})
  end

  @doc """
  Remove the specified reconnect token from the store.
  """
  @spec delete(reconnect_token()) :: :ok
  def delete(reconnect_token) do
    GenServer.call(@global_name, {:delete, reconnect_token})
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
