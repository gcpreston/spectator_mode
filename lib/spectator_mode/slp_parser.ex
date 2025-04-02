defmodule SpectatorMode.SlpParser do
  @moduledoc """
  The absolute minimum .slp parsing needed for this application.
  """

  @doc """
  Determine which [Slippi event type](https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md#events)
  the given packet corresponds to.

  Please note that this function assumes events are successfully grouped as a
  frame as indicated by the [spectator protocol docs](https://github.com/project-slippi/slippi-wiki/blob/master/SPECTATOR_PROTOCOL.md#slp-streams),
  and assuming Event Payloads and Game Start come in the same packet.

  Since it is stated that this behavior should not be relied upon, this will
  have to be improved eventually.
  """
  def packet_type(<<command, __rest::binary>>) do
    case command do
      0x35 -> :event_payloads
      0x39 -> :game_end
      _ -> :other
    end
  end
end
