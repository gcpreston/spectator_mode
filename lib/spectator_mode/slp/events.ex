defmodule SpectatorMode.Slp.Events do
  @type t :: EventPayloads.t() | GameStart.t() | GameEnd.t()
  @type payload_sizes :: %{integer() => integer()}

  defmodule EventPayloads do
    @type t :: %__MODULE__{
      binary: binary(),
      payload_sizes: Events.payload_sizes()
    }
    @enforce_keys [:payload_sizes, :binary]
    defstruct [:payload_sizes, :binary]
  end

  defmodule GameStart do
    @type player_settings :: %{
      port: number(),
      player_type: number(),
      external_character_id: integer(),
      display_name: String.t(),
      connect_code: String.t()
    }

    @type t :: %__MODULE__{
      binary: binary(),
      players: {
        player_settings(),
        player_settings(),
        player_settings(),
        player_settings()
      },
      stage_id: integer()
    }
    @enforce_keys [:binary, :players, :stage_id]
    defstruct [:binary, :players, :stage_id]
  end

  defmodule GameEnd do
    @type t :: %__MODULE__{
      binary: binary()
    }
    @enforce_keys [:binary]
    defstruct [:binary]
  end

  defmodule FodPlatforms do
    @type t :: %__MODULE__{
      binary: binary(),
      frame_number: integer(),
      platform: :left | :right,
      height: float()
    }
    @enforce_keys [:binary, :frame_number, :platform, :height]
    defstruct [:binary, :frame_number, :platform, :height]
  end
end
