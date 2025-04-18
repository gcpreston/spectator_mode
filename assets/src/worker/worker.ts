import { CommandPayloadSizes } from "~/common/types";
import { parsePacket } from "~/worker/liveParser";

/**
 * Message schemas
 *
 * Inputs (event.data):
 * - { type: "connect", value: <wsUrl string> }
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

function connectWS(wsUrl: string) {
  const ws = new WebSocket(wsUrl);
  ws.binaryType = "arraybuffer";

  ws.onmessage = (msg) => {
    handleGameData(msg.data);
  };

  ws.onerror = (err) => {
    console.error("WebSocket error:", err);
  }

  ws.onclose = (msg) => {
    console.log("WebSocket closed:", msg);
  }
}

function handleGameData(payload: ArrayBuffer) {
  const gameEvents = parsePacket(
    new Uint8Array(payload),
    workerState
  );
  postMessage({ type: "game_data", value: gameEvents });
}
