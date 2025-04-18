import { createMemo, For, Show } from "solid-js";
import { Camera } from "~/components/viewer/Camera";
import { HUD } from "~/components/viewer/HUD";
import { Players } from "~/components/viewer/Player";
import { Stage } from "~/components/viewer/Stage";
import { Item } from "~/components/viewer/Item";
import { SpectateControls } from "./SpectateControls";
import { nonReactiveState, spectateStore } from "~/state/spectateStore";

export function Viewer() {
  const items = createMemo(
    () => nonReactiveState.gameFrames[spectateStore.frame]?.items ?? []
  );
  const showState = () => {
    console.log('spectateStore', spectateStore);
    console.log('nonReactiveState', nonReactiveState);
  };
  return (
    <div class="flex flex-col overflow-y-auto pb-4">
      {spectateStore.isDebug && <button onClick={showState}>Debug</button>}
      <Show
        when={spectateStore.playbackData?.settings && nonReactiveState.gameFrames.length > spectateStore.frame}
        fallback={<div class="flex justify-center italic">Waiting for game...</div>}
      >
        <svg class="rounded-t border bg-slate-50" viewBox="-365 -300 730 600">
          {/* up = positive y axis */}
          <g class="-scale-y-100">
            <Camera>
              <Stage />
              <Players />
              <For each={items()}>{(item) => <Item item={item} />}</For>
            </Camera>
            <HUD />
          </g>
        </svg>
        <SpectateControls />
      </Show>
    </div>
  );
}
