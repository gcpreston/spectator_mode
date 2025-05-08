defmodule SpectatorMode.StreamsTest do
  use ExUnit.Case, async: false

  alias SpectatorMode.Streams

  # TODO: Clean up dummy sources
  # can create a test support genserver which is started with start_supervised

  defp dummy_source do
    spawn(fn ->
      receive do
        :crash -> raise "Some error occurred!"
      end
    end)
  end

  describe "start_and_link_relay/1" do
    test "starts a relay and links the calling process by default" do
      Streams.subscribe()

      assert {:ok, relay_pid, bridge_id, _reconnect_token} = Streams.start_and_link_relay()
      assert_receive {:relay_created, ^bridge_id}

      Process.flag(:trap_exit, true)
      Process.exit(relay_pid, :bridge_quit)
      assert_receive {:EXIT, ^relay_pid, :bridge_quit}
      assert_receive {:relay_destroyed, ^bridge_id}
    end
  end

  describe "reconnect_relay/2" do
    test "reconnects the relay and links the calling process by default" do
      Streams.subscribe()
      source_pid = dummy_source()
      {:ok, relay_pid, bridge_id, reconnect_token} = Streams.start_and_link_relay(source_pid)

      send(source_pid, :crash)
      assert_receive {:bridge_disconnected, ^bridge_id}

      new_source_pid = dummy_source()

      assert {:ok, ^relay_pid, ^bridge_id, new_reconnect_token} =
               Streams.reconnect_relay(reconnect_token, new_source_pid)

      assert reconnect_token != new_reconnect_token
      assert_receive {:bridge_reconnected, ^bridge_id}
    end
  end
end
