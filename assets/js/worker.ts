import { CommandPayloadSizes } from "~/common/types";
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

export type WorkerState = {
  /**
   * The version of the .slp spec that was used when the file was created. Some
   * fields are only present after certain versions.
   */
  replayFormatVersion?: string,
  payloadSizes?: CommandPayloadSizes
};

const workerState: WorkerState = {
  replayFormatVersion: undefined,
  payloadSizes: undefined
};

onmessage = (event: MessageEvent<WorkerInput>) => {
  switch (event.data.type) {
    case "connect":
      connectWS(event.data.value);
      break;
  }
};

function connectWS(bridgeId: string) {
  console.log("Connecting to bridge:", bridgeId);
  const PHOENIX_URL = "/viewer_socket/websocket?bridge_id=" + bridgeId;
  const ws = new WebSocket(PHOENIX_URL);
  console.log("Connected to viewer socket with bridge_id:", bridgeId);

  ws.onmessage = (msg) => {
    msg.data.arrayBuffer()
      .then((ab: ArrayBuffer) => {
        handleGameData(ab);
      });
  };

  ws.onerror = (err) => {
    console.error("WebSocket error:", err);
  }
}

function handleGameData(payload: ArrayBuffer) {
  const gameEvents = parsePacket(
    new Uint8Array(payload),
    workerState
  );
  postMessage({ type: "game_data", value: gameEvents });
}
