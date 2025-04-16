defmodule SpectatorMode.Slp.ParserTest do
  use ExUnit.Case

  describe "Game Start event" do
    test "parses display names" do
      # <<84, 101, 115, 116, 87, 105, 108, 108, 83, 68, 83, 111, 114, 114, 121, 0>>
      # <<103, 108, 104, 102, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
    end
  end
end
