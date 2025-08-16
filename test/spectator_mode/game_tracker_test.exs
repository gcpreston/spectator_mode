defmodule SpectatorMode.GameTrackerTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.GameTracker
  alias SpectatorMode.Slp.EventsFixtures

  setup do
    %{stream_id: "game_tracker_test_id"}
  end

  describe "initialize, list, and delete streams" do
    test "initialize_stream/1 sets appropriate keys", %{stream_id: stream_id} do
      assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) |> Enum.empty?()
      assert GameTracker.join_payload(stream_id) == <<>>

      GameTracker.initialize_stream(stream_id)

      assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) == [%{stream_id: stream_id, active_game: nil}]
      assert GameTracker.join_payload(stream_id) == <<>>
    end

    test "delete/1 removes stream data", %{stream_id: stream_id} do
      event_payloads = EventsFixtures.event_payloads_fixture()
      game_start = EventsFixtures.game_start_fixture()
      fod_platform = EventsFixtures.fod_platforms_fixture()

      GameTracker.initialize_stream(stream_id)
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
end
