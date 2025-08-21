defmodule SpectatorMode.Slp.EventsFixtures do
  def event_payloads_fixture do
    %SpectatorMode.Slp.Events.EventPayloads{
      payload_sizes: %{
        16 => 516,
        54 => 760,
        55 => 66,
        56 => 84,
        57 => 6,
        58 => 12,
        59 => 44,
        60 => 8,
        61 => 57632,
        63 => 9,
        64 => 5,
        65 => 8
      },
      binary: <<53, 37, 54, 2, 248, 55, 0, 66, 56, 0, 84, 57, 0, 6, 58, 0, 12, 59,
        0, 44, 60, 0, 8, 61, 225, 32, 16, 2, 4, 63, 0, 9, 64, 0, 5, 65, 0, 8>>
    }
  end

  def game_start_fixture do
    %SpectatorMode.Slp.Events.GameStart{
      binary: <<54, 3, 19, 0, 0, 50, 1, 134, 76, 195, 0, 0, 0, 0, 0, 0, 255, 255,
        110, 0, 2, 0, 0, 1, 224, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255,
        255, 255, 255, 255, 255, 0, 0, 0, 0>>,
      players: {%{
        port: 1,
        display_name: "",
        external_character_id: 26,
        player_type: 3,
        connect_code: ""
      },
      %{
        port: 2,
        display_name: "",
        external_character_id: 2,
        player_type: 0,
        connect_code: ""
      },
      %{
        port: 3,
        display_name: "",
        external_character_id: 3,
        player_type: 1,
        connect_code: ""
      },
      %{
        port: 4,
        display_name: "",
        external_character_id: 26,
        player_type: 3,
        connect_code: ""
      }},
      stage_id: 2
    }
  end

  def fod_platforms_fixture do
    %SpectatorMode.Slp.Events.FodPlatforms{
      binary: <<63, 0, 0, 3, 220, 1, 65, 59, 51, 18>>,
      frame_number: 1111,
      platform: :left,
      height: 11.699968338012695
    }
  end
end
