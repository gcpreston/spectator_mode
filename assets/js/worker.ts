import { Socket } from "phoenix";
import { parsePacket } from "./liveParser";

/**
 * Message schemas
 *
 * Inputs (event.data):
 * - { type: "connect", value: <bridgeId string> }
 * - disconnect?
 *
 * Outputs:
 * - { type: "game_data", value: GameEvent[] }
 */

type WorkerInput = { type: "connect", value: string };

onmessage = (event: MessageEvent<WorkerInput>) => {
  console.log("worker got event", event);

  switch (event.data.type) {
    case "connect":
      connectWS(event.data.value);
      break;
  }

  /*


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

function binaryToGameEvents(buf: ArrayBuffer) {
  const gameEvents = parsePacket(
    new Uint8Array(buf),
    replayState.playbackData // TODO: Store payloadSizes here
  );
}
