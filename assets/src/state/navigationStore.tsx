import { createSignal } from "solid-js";

export type Sidebar = "local replays" | "clips" | "inputs";

export const [currentSidebar, setSidebar] =
  createSignal<Sidebar>("local replays");
