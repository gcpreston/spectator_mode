defmodule SpectatorMode.ShiftJis do
  @shift_jis "VENDORS/MICSFT/WINDOWS/CP932"

  @doc ~S"""
      iex> test = ShiftJis.encode("テスト")
      <<131, 101, 131, 88, 131, 103>>
      iex> ShiftJis.decode(test)
      "テスト"
  """

  def encode(str), do: Codepagex.from_string!(str, @shift_jis)
  def decode(str), do: Codepagex.to_string!(str, @shift_jis)
end
