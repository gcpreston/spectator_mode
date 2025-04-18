import { customElement } from "solid-element";
import { MiniApp } from "~/components/MiniApp";
import { setWsUrl } from "~/state/spectateStore";

interface HTMLSlippiViewer extends HTMLElement {
  spectate(wsUrl: string | null): void;
}

customElement("slippi-viewer", { zipsBaseUrl: "/" },
  (props, { element }) => {
    element.spectate = setWsUrl
    return (<MiniApp zipsBaseUrl={props.zipsBaseUrl} /> as HTMLSlippiViewer);
  });
