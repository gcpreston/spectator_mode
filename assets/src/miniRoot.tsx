import { render } from "solid-js/web";
import { MiniApp } from "~/components/MiniApp";
import { createWorker } from "./workerUtil";

const root = document.querySelector("#viewer-root");

if (root !== null) {
  const bridgeId = root.getAttribute("bridgeid");

  if (bridgeId !== null) {
    createWorker(bridgeId);
    render(() => <MiniApp />, root);
  }
}
