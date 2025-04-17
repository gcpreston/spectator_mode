import { customElement } from "solid-element";
import { MiniApp } from "~/components/MiniApp";
import { setBridgeId } from "~/state/spectateStore";

interface HTMLSlippiViewer extends HTMLElement {
  setBridgeId(bridgeId: string): void;
}

customElement('slippi-viewer', {},
  (_props, { element }) => {
    element.setBridgeId = setBridgeId;
    return (<MiniApp /> as HTMLSlippiViewer);
  });
