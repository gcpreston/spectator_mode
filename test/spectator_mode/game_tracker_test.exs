defmodule SpectatorMode.GameTrackerTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.GameTracker
  alias SpectatorMode.Slp.EventsFixtures

  test "initialize_stream/1 sets appropriate keys, delete/1 removes stream data" do
    event_payloads = EventsFixtures.event_payloads_fixture()
    game_start = EventsFixtures.game_start_fixture()
    fod_platform = EventsFixtures.fod_platforms_fixture()

    stream_id = GameTracker.initialize_stream()
    GameTracker.set_event_payloads(stream_id, event_payloads)
    GameTracker.set_game_start(stream_id, game_start)
    GameTracker.set_fod_platform(stream_id, fod_platform.platform, fod_platform)

    assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) == [%{stream_id: stream_id, active_game: game_start}]
    assert GameTracker.join_payload(stream_id) == event_payloads.binary <> game_start.binary <> fod_platform.binary

    GameTracker.delete(stream_id)

    assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) |> Enum.empty?()
    assert GameTracker.join_payload(stream_id) == <<>>
  end
end
