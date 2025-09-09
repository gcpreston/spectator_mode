defmodule SpectatorMode.Events do
  @moduledoc """
  Definitions for events which can be sent over PubSub.
  """
  alias SpectatorMode.Streams
  alias SpectatorMode.Slp.SlpEvents

  defmodule LivestreamCreated do
    @type t() :: %__MODULE__{
      stream_id: Streams.stream_id(),
      node_name: node(),
      game_start: %SlpEvents.GameStart{} | nil,
      disconnected: boolean()
    }
    @enforce_keys [:stream_id]
    defstruct stream_id: nil, node_name: Node.self(), game_start: nil, disconnected: false
  end

  defmodule LivestreamDestroyed do
    @type t() :: %__MODULE__{stream_id: Streams.stream_id()}
    @enforce_keys [:stream_id]
    defstruct stream_id: nil
  end

  defmodule LivestreamDisconnected do
    @type t() :: %__MODULE__{stream_id: Streams.stream_id()}
    @enforce_keys [:stream_id]
    defstruct stream_id: nil
  end

  defmodule LivestreamReconnected do
    @type t() :: %__MODULE__{stream_id: Streams.stream_id()}
    @enforce_keys [:stream_id]
    defstruct stream_id: nil
  end

  defmodule GameStart do
    @type t() :: %__MODULE__{
      stream_id: Streams.stream_id(),
      game_start: %SlpEvents.GameStart{}
    }
    @enforce_keys [:stream_id, :game_start]
    defstruct stream_id: nil, game_start: nil
  end

  defmodule GameEnd do
    @type t() :: %__MODULE__{stream_id: Streams.stream_id()}
    @enforce_keys [:stream_id]
    defstruct stream_id: nil
  end
end
