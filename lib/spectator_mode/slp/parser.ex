defmodule SpectatorMode.Slp.Parser do
  @moduledoc """
  The absolute minimum .slp parsing needed for this application.

  Slippi spec reference: https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md
  """

  @type payload_sizes :: %{integer() => integer()}

  defmodule Events do
    @type t :: EventPayloads.t() | GameStart.t()

    defmodule EventPayloads do
      @type t :: %__MODULE__{
        binary: binary(),
        payload_sizes: Slp.Parser.payload_sizes()
      }
      @enforce_keys [:payload_sizes, :binary]
      defstruct [:payload_sizes, :binary]
    end

    defmodule GameStart do
      @type player_settings :: %{external_character_id: integer()}

      @type t :: %__MODULE__{
        binary: binary(),
        players: {
          player_settings(),
          player_settings(),
          player_settings(),
          player_settings()
        }
      }
      @enforce_keys [:binary, :players]
      defstruct [:binary, :players]
    end

    defmodule GameEnd do
      @type t :: %__MODULE__{
        binary: binary()
      }
      @enforce_keys [:binary]
      defstruct [:binary]
    end
  end

  defmodule ParseError do
    defexception [:message]
  end

  @doc """
  Parse a binary game data packet, which may include multiple events.

  Parsing requires knowing the sizes of each possible event, as given in the
  Event Payloads event. This is the first event in the stream, and also needs
  to be parsed, and therefore may not be present on call. If Event Payloads
  is not given, and the first command to be parsed is not Event Payloads,
  `ParseError` is raised.
  """
  @spec parse_packet(binary(), payload_sizes() | nil) :: [Events.t()]
  def parse_packet(data, payload_sizes) do
    <<first_command::8, _rest::binary>> = data

    if is_nil(payload_sizes) && first_command != 0x35 do
      raise ParseError, message: "Expected first command to be 0x35, got: 0x#{Integer.to_string(first_command, 16)}"
    end

    parse_packet(data, payload_sizes, [])
  end

  defp parse_packet(<<>>, _payload_sizes, acc), do: Enum.reverse(acc)

  defp parse_packet(<<0x35::8, _::binary>> = data, _payload_sizes, []) do
    {event_payloads, rest} = parse_event_payloads(data)
    parse_packet(rest, event_payloads.payload_sizes, [event_payloads])
  end

  defp parse_packet(<<command::8, _::binary>> = data, payload_sizes, acc) do
    {event, rest} =
      case command do
        0x36 -> parse_game_start(data, payload_sizes)
        0x39 -> parse_game_end(data, payload_sizes)
        _ -> parse_skip(data, payload_sizes)
      end

    new_acc = if is_nil(event), do: acc, else: [event | acc]
    parse_packet(rest, payload_sizes, new_acc)
  end

  # https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md#event-payloads
  defp parse_event_payloads(<<0x35::8, payload_size::8, rest::binary>>) do
    <<ep_data::binary-size(payload_size - 1), rest::binary>> = rest
    binary = <<0x35::8, payload_size::8, ep_data::binary>>
    {%Events.EventPayloads{payload_sizes: parse_payload_sizes(ep_data, %{}), binary: binary}, rest}
  end

  defp parse_payload_sizes(<<>>, acc), do: acc

  defp parse_payload_sizes(<<command::8, payload_size::16, rest::binary>>, acc) do
    parse_payload_sizes(rest, Map.put(acc, command, payload_size))
  end

  # payload_sizes does not include the command byte, but the spec includes
  # the command byte in the offset table.
  # To more easily follow the spec, the command byte is expected to be passed
  # to parser functions, so that offsets line up with the spec. This means
  # that the size computations will include a +1.

  defp parse_game_start(data, payload_sizes) do
    game_start_size = 1 + payload_sizes[0x36]
    <<gs_data::binary-size(game_start_size), rest::binary>> = data

    player_settings =
      for i <- 0..3 do
        %{external_character_id: read_uint8(data, 0x5 + 0x60 + (0x24 * i))}
      end
      |> List.to_tuple()

    {%Events.GameStart{players: player_settings, binary: gs_data}, rest}
  end

  defp parse_game_end(data, payload_sizes) do
    game_end_size = 1 + payload_sizes[0x39]
    <<ge_data::binary-size(game_end_size), rest::binary>> = data
    {%Events.GameEnd{binary: ge_data}, rest}
  end

  defp parse_skip(<<command::8, _::binary>> = data, payload_sizes) do
    payload_size = 1 + payload_sizes[command]
    <<_event_data::binary-size(payload_size), rest::binary>> = data
    {nil, rest}
  end

  defp read_uint8(data, offset) do
    <<_::binary-size(offset), n::8, _::binary>> = data
    n
  end
end
