defmodule SpectatorMode.Slp.Parser do
  @moduledoc """
  The absolute minimum .slp parsing needed for this application.

  Slippi spec reference: https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md
  """

  ## DEFINITIONS
  # "payload size" :: The size of a Slippi event without the command byte.
  #                   This is the value of the Payload Size field in the spec.
  # "event size"   :: The size of a Slippi event with the command byte.
  #
  # A Slippi data stream is therefore expected to look as follows:
  #   <event payloads>, command byte, payload size # bytes, command byte, payload size # bytes, ...
  # or
  #   <event payloads>, event size # bytes, event size # bytes, ...

  alias SpectatorMode.Slp.SlpEvents

  @display_name_max_length 31
  @connect_code_max_length 10

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

  Returns an array of parsed events, and any leftover binary that did not fit
  the size given by Event Payloads.
  """
  @spec parse_packet(binary(), SlpEvents.payload_sizes() | nil) :: {[SlpEvents.t()], binary()}
  def parse_packet(data, payload_sizes) do
    <<first_command::8, _rest::binary>> = data

    if is_nil(payload_sizes) && first_command != 0x35 do
      raise ParseError, message: "Expected first command to be 0x35, got: 0x#{Integer.to_string(first_command, 16)}"
    end

    parse_packet(data, payload_sizes, [])
  end

  defp parse_packet(<<>>, _payload_sizes, acc), do: {Enum.reverse(acc), <<>>}

  defp parse_packet(<<0x35::8, _::binary>> = data, _payload_sizes, []) do
    {event_payloads, rest} = parse_event_payloads(data)
    parse_packet(rest, event_payloads.payload_sizes, [event_payloads])
  end

  defp parse_packet(<<command::8, payload_and_rest::binary>> = data, payload_sizes, acc) do
    with {:ok, payload_size} <- Map.fetch(payload_sizes, command),
         true <- byte_size(payload_and_rest) >= payload_size do
      # Valid command with full data for next event
      {event, rest} =
        case command do
          0x36 -> parse_game_start(data, payload_size)
          0x39 -> parse_game_end(data, payload_size)
          0x3f -> parse_fod_platforms(data, payload_size)
          _ -> parse_skip(data, payload_size)
        end

      new_acc = if is_nil(event), do: acc, else: [event | acc]
      parse_packet(rest, payload_sizes, new_acc)
    else
      :error ->
        # Unknown command; error case
        raise ParseError, message: "Attempted to parse unknown command 0x#{Integer.to_string(command, 16)} (payload sizes: #{inspect(payload_sizes)})"

      false ->
        # Last event got cut off; return with leftover
        {Enum.reverse(acc), data}
    end
  end

  defp parse_event_payloads(<<0x35::8, payload_size::8, rest::binary>>) do
    <<ep_data::binary-size(payload_size - 1), rest::binary>> = rest
    binary = <<0x35::8, payload_size::8, ep_data::binary>>
    {%SlpEvents.EventPayloads{payload_sizes: parse_payload_sizes(ep_data, %{}), binary: binary}, rest}
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

  defp parse_game_start(data, payload_size) do
    event_size = 1 + payload_size
    <<gs_data::binary-size(event_size), rest::binary>> = data

    player_settings =
      for i <- 0..3 do
        %{
          port: i + 1,
          player_type: read_uint8(data, 0x5 + 0x61 + (0x24 * i)),
          external_character_id: read_uint8(data, 0x5 + 0x60 + (0x24 * i)),
          display_name: read_shift_jis_string(data, 0x1a5 + (0x1f * i), @display_name_max_length),
          connect_code: read_shift_jis_string(data, 0x221 + (0xa * i), @connect_code_max_length)
        }
      end
      |> List.to_tuple()

    stage_id = read_uint16(data, 0x5 + 0xe)

    {%SlpEvents.GameStart{players: player_settings, stage_id: stage_id, binary: gs_data}, rest}
  end

  defp parse_game_end(data, payload_size) do
    event_size = 1 + payload_size
    <<ge_data::binary-size(event_size), rest::binary>> = data
    {%SlpEvents.GameEnd{binary: ge_data}, rest}
  end

  defp parse_fod_platforms(data, payload_size) do
    event_size = 1 + payload_size
    <<ge_data::binary-size(event_size), rest::binary>> = data

    {
      %SlpEvents.FodPlatforms{
        binary: ge_data,
        frame_number: read_int32(data, 0x1) + 123,
        platform: (if read_uint8(data, 0x5) == 1, do: :left, else: :right),
        height: read_float(data, 0x6)
      },
      rest
    }
  end

  defp parse_skip(data, payload_size) do
    event_size = 1 + payload_size
    <<_event_data::binary-size(event_size), rest::binary>> = data
    {nil, rest}
  end

  defp read_uint8(data, offset) do
    <<_::binary-size(offset), n::size(8)-unsigned, _::binary>> = data
    n
  end

  defp read_uint16(data, offset) do
    <<_::binary-size(offset), n::size(16)-unsigned, _::binary>> = data
    n
  end

  defp read_int32(data, offset) do
    <<_::binary-size(offset), n::size(32)-signed, _::binary>> = data
    n
  end

  defp read_float(data, offset) do
    <<_::binary-size(offset), n::size(32)-float, _::binary>> = data
    n
  end

  defp read_shift_jis_string(data, offset, max_length) do
    Enum.reduce_while(0..(max_length - 1), <<>>, fn char_num, acc ->
      byte = read_uint8(data, offset + char_num)

      if byte == 0 do
        {:halt, acc}
      else
        {:cont, <<acc::binary, byte>>}
      end
    end)
    |> SpectatorMode.ShiftJis.decode()
  end
end
