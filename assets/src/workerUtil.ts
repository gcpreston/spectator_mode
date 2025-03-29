import { Socket } from "phoenix";

export function createWorker(bridgeId: string) {
  console.log('creating worker...');
  const worker = new Worker('/assets/worker.js', { type: "module" });

  worker.onmessage = (event) => {
    console.log(`Got: ${event.data}`);
  };

  worker.onerror = (error) => {
    console.log(`Worker error: ${error.message}`);
    throw error;
  };

  const postWorker = () => {
    worker.postMessage("ping");
  }

  return postWorker;
}
