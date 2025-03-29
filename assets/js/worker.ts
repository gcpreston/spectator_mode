import { Socket } from "phoenix";
import { add } from "./liveParser";

onmessage = (event) => {
  console.log("worker got event", event);
  console.log(add(5));

  const bridgeId = 'test_bridge';

  console.log('connecting to bridge', bridgeId);
  const PHOENIX_URL = '/socket';
  const socket = new Socket(PHOENIX_URL);

  socket.connect();

  const phoenixChannel = socket.channel("view:" + bridgeId);
  phoenixChannel.join()
    .receive("ok", (resp: any) => {
      console.log("Joined successfully", resp);

      phoenixChannel.on("game_data", (payload: ArrayBuffer) => {
       console.log('got payload', payload);
      });
    })
    .receive("error", (resp: any) => {
      console.log('WebSocket error:', resp);
    });

  /*
  const buf = replayState.packetBuffer[0];
  const bufferRest = replayState.packetBuffer.slice(1);
  setReplayState("packetBuffer", bufferRest);

  const gameEvents = parsePacket(
    new Uint8Array(buf),
    replayState.playbackData
  );

  batch(() => {
    gameEvents.forEach((gameEvent) => {
      setReplayStateFromGameEvent(gameEvent)
    });
  });
  */
};

function connectWS(bridgeId: string) {
  console.log("connecting to bridge", bridgeId);
  const PHOENIX_URL = "/socket";
  const socket = new Socket(PHOENIX_URL);

  socket.connect();

  const phoenixChannel = socket.channel("view:" + bridgeId);
  phoenixChannel.join()
    .receive("ok", (resp: any) => {
      console.log("Joined successfully", resp);
      self.postMessage('Connected from web worker :)')

      phoenixChannel.on("game_data", (payload) => {
        console.log("got game data", payload);
      });
    })
    .receive("error", (resp) => {
      console.log("WebSocket error:", resp);
    });
}
