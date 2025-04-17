import { customElement } from "solid-element";
import { MiniApp } from "~/components/MiniApp";
import { setBridgeId } from "~/state/spectateStore";

const SlippiViewerConstructor = customElement('slippi-viewer', {}, MiniApp);
HTMLElement.prototype.setBridgeId = setBridgeId;
console.log('new version btw');
