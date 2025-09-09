defmodule SpectatorMode.GameTrackerTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.Events
  alias SpectatorMode.GameTracker
  alias SpectatorMode.Slp.EventsFixtures

  describe "start_link/1" do
    test "does not allow multiple instances; creates a link anyways" do
      pid = GenServer.whereis(GameTracker)
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

    # Initialize and check initial data
    stream_id = GameTracker.initialize_stream()
    assert GameTracker.list_local_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) == [%{stream_id: stream_id, game_start: nil}]
    assert GameTracker.minimal_join_payload(stream_id) == <<>>

    # Check data after processing packets
    # TODO: handle_packet sends out events about the game, which StreamsStore receives
    #   But this will cause an error in the test unless StreamsStore first receives LivestreamCreated
    #   This feels like unwanted coupling
    send(SpectatorMode.StreamsStore, %Events.LivestreamCreated{stream_id: stream_id})

    SpectatorMode.Streams.subscribe()
    GameTracker.handle_packet(stream_id, event_payloads.binary)
    GameTracker.handle_packet(stream_id, game_start.binary)
    GameTracker.handle_packet(stream_id, fod_platform.binary)
    assert_receive %Events.GameStart{stream_id: ^stream_id, game_start: game_start_received}
    assert game_start_received.binary == game_start.binary
    assert GameTracker.list_local_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) == [%{stream_id: stream_id, game_start: game_start}]
    assert GameTracker.minimal_join_payload(stream_id) == event_payloads.binary <> game_start.binary <> fod_platform.binary

    # Check data after removing stream
    GameTracker.delete(stream_id)
    assert GameTracker.list_local_streams() |> Enum.filter(fn %{stream_id: test_stream_id} -> test_stream_id == stream_id end) |> Enum.empty?()
    assert GameTracker.minimal_join_payload(stream_id) == <<>>

    # Manually check that no keys remain
    assert :ets.select(:livestreams, [{{{stream_id, :_}, :"$1"}, [], [:"$1"]}]) |> length() == 0
  end
end
