import { render } from "solid-js/web";
import { MiniApp } from "~/components/MiniApp";
import { createWorker } from "./workerUtil";


const root = document.querySelector("#root");
if (root !== null) {
  const bridgeId = root.getAttribute("bridgeid");

  if (bridgeId !== null) {
    const postWorker = createWorker(bridgeId);
    render(() => <MiniApp bridgeId={bridgeId} postWorker={postWorker} />, root);
  }
}
