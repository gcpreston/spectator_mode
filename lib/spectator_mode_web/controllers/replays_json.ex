defmodule SpectatorModeWeb.ReplaysJSON do
  @doc """
  Renders a list of available replays.
  """
  def index(%{replays: replays}) do
    %{replays: for(replay <- replays |> Enum.filter(fn r -> !is_nil(r.active_game) end), do: data(replay))}
  end

  # TODO: This is obviously gross
  #   Makes me think there should be a proper struct for the return value of list_streams/0
  defp data(%{stream_id: stream_id}) do
    %{
      game_info: %{
        console_name: "louloute",
        error: false
      },
      filename: "#{stream_id}.slp",
      is_active_transfer: true,
      modified_time: DateTime.utc_now()
    }
  end
end
