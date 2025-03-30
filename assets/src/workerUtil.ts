import { batch } from "solid-js";
import { GameEvent } from "~/common/types";
import { setReplayStateFromGameEvent } from "~/state/spectateStore";

export function createWorker(bridgeId: string) {
  console.log('creating worker...');
  const worker = new Worker('/assets/worker.js', { type: "module" });

  worker.onmessage = (event: MessageEvent) => {
    const gameEvents: GameEvent[] = event.data.value;

    batch(() => {
      gameEvents.forEach((gameEvent) => {
        setReplayStateFromGameEvent(gameEvent)
      });
    });
  };

  worker.onerror = (error) => {
    console.log(`Worker error: ${error.message}`);
    throw error;
  };

  const postWorker = () => {
    worker.postMessage({ type: "connect", value: bridgeId });
  }

  return postWorker;
}
