import { createMemo, createSignal } from "solid-js";
import { replayStore } from "~/state/replayStore";
import { spectateStore } from "~/state/spectateStore";

export type PlaybackType = "replay" | "spectate";
export const [playbackType, setPlaybackType] = createSignal<PlaybackType>("replay");

export const playbackStore = createMemo(() => {
  switch (playbackType()) {
    case "replay": return replayStore;
    case "spectate": return spectateStore;
  }
})
