defmodule SpectatorMode.GameTrackerTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.GameTracker
  alias SpectatorMode.Slp.EventsFixtures

  describe "start_link/1" do
    test "does not allow multiple instances; creates a link anyways" do
      pid = GenServer.whereis({:global, GameTracker})
      assert is_pid(pid)
      assert {:ok, ^pid} = GameTracker.start_link([])

      Process.flag(:trap_exit, true)
      Process.exit(pid, :kill)

      assert_receive {:EXIT, ^pid, _reason}
    end
  end

  test "initialize_stream/1 sets appropriate keys, delete/1 removes stream data" do
    event_payloads = EventsFixtures.event_payloads_fixture()
    game_start = EventsFixtures.game_start_fixture()
    fod_platform = EventsFixtures.fod_platforms_fixture()

    # Initialize stream and events
    stream_id = GameTracker.initialize_stream()
    GameTracker.set_event_payloads(stream_id, event_payloads)
    GameTracker.set_game_start(stream_id, game_start)
    GameTracker.set_fod_platform(stream_id, fod_platform.platform, fod_platform)

    # List tracked data
    assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) == [%{stream_id: stream_id, active_game: game_start}]
    assert GameTracker.join_payload(stream_id) == event_payloads.binary <> game_start.binary <> fod_platform.binary

    # Delete and re-list
    GameTracker.delete(stream_id)
    assert GameTracker.list_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) |> Enum.empty?()
    assert GameTracker.join_payload(stream_id) == <<>>

    # Manually check that no keys remain
    assert :ets.select(:livestreams, [{{{stream_id, :_}, :"$1"}, [], [:"$1"]}]) |> length() == 0
  end
end
