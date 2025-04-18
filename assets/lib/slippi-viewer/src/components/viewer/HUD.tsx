import { createMemo } from "solid-js";
import { For } from "solid-js/web";
import { spectateStore } from "~/state/spectateStore";
import { PlayerHUD } from "~/components/viewer/PlayerHUD";
import { Timer } from "~/components/viewer/Timer";

export function HUD() {
  const playerIndexes = createMemo(() =>
    spectateStore
      .playbackData!.settings.playerSettings.filter(Boolean)
      .map((playerSettings) => playerSettings.playerIndex)
  );
  return (
    <>
      <Timer />
      <For each={playerIndexes()}>
        {(playerIndex) => <PlayerHUD player={playerIndex} />}
      </For>
    </>
  );
}
