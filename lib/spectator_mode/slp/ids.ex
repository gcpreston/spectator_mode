defmodule SpectatorMode.SlpIds do
  @moduledoc """
  Helpers for SSBM IDs found in Slippi.

  Reference: https:#docs.google.com/spreadsheets/d/1JX2w-r2fuvWuNgGb6D3Cs4wHQKLFegZe2jhbBuIhCG8/preview#gid=20
  """

  @character_name_by_external_id {
    "Captain Falcon", # 0, 0x0
    "Donkey Kong", # 1, 0x1
    "Fox", # 2, 0x2
    "Mr. Game & Watch", # 3, 0x3
    "Kirby", # 4, 0x4
    "Bowser", # 5, 0x5
    "Link", # 6, 0x6
    "Luigi", # 7, 0x7
    "Mario", # 8, 0x8
    "Marth", # 9, 0x9
    "Mewtwo", # 10, 0xa
    "Ness", # 11, 0xb
    "Peach", # 12, 0xc
    "Pikachu", # 13, 0xd
    "Ice Climbers", # 14, 0xe
    "Jigglypuff", # 15, 0xf
    "Samus", # 16, 0x10
    "Yoshi", # 17, 0x11
    "Zelda", # 18, 0x12
    "Sheik", # 19, 0x13
    "Falco", # 20, 0x14
    "Young Link", # 21, 0x15
    "Dr. Mario", # 22, 0x16
    "Roy", # 23, 0x17
    "Pichu", # 24, 0x18
    "Ganondorf", # 25, 0x19
    "Master Hand", # 26, 0x1a
    "Wireframe Male", # 27, 0x1b
    "Wireframe Female", # 28, 0x1c
    "Giga Bowser", # 29, 0x1d
    "Crazy Hand", # 30, 0x1e
    "Sandbag", # 31, 0x1f
    "Popo", # 32, 0x20
  }

  @stage_name_by_external_id {
    "Dummy", # 0, 0x0
    "TEST", # 1, 0x1
    "Fountain of Dreams", # 2, 0x2
    "Pokémon Stadium", # 3, 0x3
    "Princess Peach's Castle", # 4, 0x4
    "Kongo Jungle", # 5, 0x5
    "Brinstar", # 6, 0x6
    "Corneria", # 7, 0x7
    "Yoshi's Story", # 8, 0x8
    "Onett", # 9, 0x9
    "Mute City", # 10, 0xa
    "Rainbow Cruise", # 11, 0xb
    "Jungle Japes", # 12, 0xc
    "Great Bay", # 13, 0xd
    "Hyrule Temple", # 14, 0xe
    "Brinstar Depths", # 15, 0xf
    "Yoshi's Island", # 16, 0x10
    "Green Greens", # 17, 0x11
    "Fourside", # 18, 0x12
    "Mushroom Kingdom I", # 19, 0x13
    "Mushroom Kingdom II", # 20, 0x14
    "Akaneia", # 21, 0x15
    "Venom", # 22, 0x16
    "Poké Floats", # 23, 0x17
    "Big Blue", # 24, 0x18
    "Icicle Mountain", # 25, 0x19
    "Icetop", # 26, 0x1a
    "Flat Zone", # 27, 0x1b
    "Dream Land N64", # 28, 0x1c
    "Yoshi's Island N64", # 29, 0x1d
    "Kongo Jungle N64", # 30, 0x1e
    "Battlefield", # 31, 0x1f
    "Final Destination", # 32, 0x20
  }

  def get_character_name_by_external_id(external_character_id) do
    elem(@character_name_by_external_id, external_character_id)
  end

  def get_stage_name_by_external_id(external_stage_id) do
    elem(@stage_name_by_external_id, external_stage_id)
  end
end
