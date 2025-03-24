import { render } from "solid-js/web";
import { MiniApp } from "~/components/MiniApp";

const root = document.querySelector("#root");
if (root !== null) {
  const bridgeId = root.getAttribute("bridgeid");
  if (bridgeId !== null) {
    render(() => <MiniApp bridgeId={bridgeId} />, root);
  }
}
