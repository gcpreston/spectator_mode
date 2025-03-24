defmodule SpectatorMode.BridgeUtils do
  @moduledoc """
  Utilities relating to bridge management.
  TODO: Come up with more permanent architecture
  """

  alias SpectatorMode.BridgeRegistry

  def list_bridges(registry \\ BridgeRegistry) do
    Registry.select(registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
end
