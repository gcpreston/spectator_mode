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

/**
 * internal use only. The size of each event is announced at the start of the
 * replay file. This is used to find the start of every event for parsing.
 */
interface CommandPayloadSizes {
  [commandByte: number]: number;
}

export type WorkerState = { payloadSizes?: CommandPayloadSizes };

const workerState: WorkerState = { payloadSizes: undefined };

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

      phoenixChannel.on("game_data", (payload: ArrayBuffer) => {
        handleGameData(payload);
      });
    })
    .receive("error", (resp) => {
      console.log("WebSocket error:", resp);
    });
}

function handleGameData(payload: ArrayBuffer) {
  const gameEvents = parsePacket(
    new Uint8Array(payload),
    workerState
  );
  postMessage({ type: "game_data", value: gameEvents });
}
