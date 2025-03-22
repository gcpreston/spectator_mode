import createRAF, { targetFPS } from "@solid-primitives/raf";
import { batch, createEffect, createResource } from "solid-js";
import { createStore } from "solid-js/store";
import {
  ActionName,
  actionNameById,
  AttackName,
  characterNameByExternalId,
  characterNameByInternalId,
} from "~/common/ids";
import {
  PlayerState,
  PlayerUpdate,
  PlayerUpdateWithNana,
  ReplayData,
  RenderData,
  ReplayStore,
} from "~/common/types";
import { parseReplay } from "~/parser/parser";
import { queries } from "~/search/queries";
import { Highlight, search } from "~/search/search";
import { currentSelectionStore } from "~/state/selectionStore";
import { CharacterAnimations, fetchAnimations } from "~/viewer/animationCache";
import { actionMapByInternalId } from "~/viewer/characters";
import { getPlayerOnFrame, getStartOfAction } from "~/viewer/viewerUtil";
import { fileStore } from "~/state/fileStore";
import { action, landsAttack } from "~/search/framePredicates";
import { getPlayerColor } from "~/common/util";
import { decode } from "@shelacek/ubjson";

export const defaultReplayStoreState: ReplayStore = {
  highlights: Object.fromEntries(
    Object.entries(queries).map(([name]) => [name, []])
  ),
  frame: 0,
  renderDatas: [],
  animations: Array(4).fill(undefined),
  fps: 60,
  framesPerTick: 1,
  running: false,
  zoom: 1,
  isDebug: false,
  isFullscreen: false,
  customAction: "Passive",
  customAttack: "Up Tilt",
};

const [replayState, setReplayState] = createStore<ReplayStore>(
  defaultReplayStoreState
);

export const replayStore = replayState;

export function selectCustomAttack(attackName: AttackName) {
  setReplayState("customAttack", attackName);
  if (replayState.playbackData) {
    setReplayState("highlights", (highlights) => ({
      ...highlights,
      customAttack: search(replayState.playbackData!, [
        { predicate: landsAttack(replayState.customAttack) },
      ]),
    }));
  }
}

export function selectCustomAction(actionName: ActionName) {
  setReplayState("customAction", actionName);
  if (replayState.playbackData) {
    setReplayState("highlights", (highlights) => ({
      ...highlights,
      customAction: search(replayState.playbackData!, [
        { predicate: action(replayState.customAction) },
      ]),
    }));
  }
}

export function selectHighlight(nameAndHighlight: [string, Highlight]) {
  batch(() => {
    setReplayState("selectedHighlight", nameAndHighlight);
    setReplayState(
      "frame",
      wrapFrame(replayState, nameAndHighlight[1].startFrame - 30)
    );
  });
}

export function nextHighlight() {
  const highlights = Object.entries(replayState.highlights).flatMap(
    ([name, highlights]) =>
      highlights.map((highlight) => [name, highlight] as const)
  );
  const currentIndex =
    replayState.selectedHighlight !== undefined
      ? highlights.findIndex(
          ([name, highlight]) => replayState.selectedHighlight![1] === highlight
        )
      : -1;
  const nextIndex = wrapHighlight(replayState, currentIndex + 1);
  batch(() => {
    setReplayState("selectedHighlight", highlights[nextIndex]);
    setReplayState("frame", highlights[nextIndex][1].startFrame - 30);
  });
}

export function previousHighlight() {
  const highlights = Object.entries(replayState.highlights).flatMap(
    ([name, highlights]) =>
      highlights.map((highlight) => [name, highlight] as const)
  );
  const currentIndex =
    replayState.selectedHighlight !== undefined
      ? highlights.findIndex(
          ([name, highlight]) => replayState.selectedHighlight![1] === highlight
        )
      : 1;
  const previousIndex = wrapHighlight(replayState, currentIndex - 1);
  batch(() => {
    setReplayState("selectedHighlight", highlights[previousIndex]);
    setReplayState("frame", highlights[previousIndex][1].startFrame - 30);
  });
}

export function speedNormal(): void {
  batch(() => {
    setReplayState("fps", 60);
    setReplayState("framesPerTick", 1);
  });
}

export function speedFast(): void {
  setReplayState("framesPerTick", 2);
}

export function speedSlow(): void {
  setReplayState("fps", 30);
}

export function zoomIn(): void {
  setReplayState("zoom", (z) => z * 1.01);
}

export function zoomOut(): void {
  setReplayState("zoom", (z) => z / 1.01);
}

export function toggleDebug(): void {
  setReplayState("isDebug", (isDebug) => !isDebug);
}

export function toggleFullscreen(): void {
  setReplayState("isFullscreen", (isFullscreen) => !isFullscreen);
}

export function togglePause(): void {
  running() ? stop() : start();
}

export function pause(): void {
  stop();
}

export function jump(target: number): void {
  setReplayState("frame", wrapFrame(replayState, target));
}

// percent is [0,1]
export function jumpPercent(percent: number): void {
  setReplayState(
    "frame",
    Math.round((replayState.playbackData?.frames.length ?? 0) * percent)
  );
}

export function adjust(delta: number): void {
  setReplayState("frame", (f) => wrapFrame(replayState, f + delta));
}

const [running, start, stop] = createRAF(
  targetFPS(
    () =>
      setReplayState("frame", (f) =>
        wrapFrame(replayState, f + replayState.framesPerTick)
      ),
    () => replayState.fps
  )
);
createEffect(() => setReplayState("running", running()));

createEffect(async () => {
  const selected = currentSelectionStore().data.selectedFileAndStub;
  if (selected === undefined) {
    setReplayState(defaultReplayStoreState);
    return;
  }

  const replayData = parseReplay(
    decode(await selected[0].arrayBuffer(), { useTypedArrays: true })
  );
  const highlights = Object.fromEntries(
    Object.entries(queries).map(([name, query]) => [
      name,
      search(replayData, ...query),
    ])
  );
  highlights.customAction = search(replayData, [
    { predicate: action(replayState.customAction) },
  ]);
  highlights.customAttack = search(replayData, [
    { predicate: landsAttack(replayState.customAttack) },
  ]);
  setReplayState({
    playbackData: replayData,
    highlights,
    frame: fileStore.urlStartFrame ?? 0,
    renderDatas: [],
  });
  if (fileStore.urlStartFrame === undefined || fileStore.urlStartFrame === 0) {
    start();
  }
});

const animationResources = [];
for (let playerIndex = 0; playerIndex < 4; playerIndex++) {
  animationResources.push(
    createResource(
      () => {
        const replay = replayState.playbackData;
        if (replay === undefined) {
          return undefined;
        }
        const playerSettings = replay.settings.playerSettings[playerIndex];
        if (playerSettings === undefined) {
          return undefined;
        }
        const playerUpdate =
          replay.frames[replayState.frame].players[playerIndex];
        if (playerUpdate === undefined) {
          return playerSettings.externalCharacterId;
        }
        if (
          playerUpdate.state.internalCharacterId ===
          characterNameByInternalId.indexOf("Zelda")
        ) {
          return characterNameByExternalId.indexOf("Zelda");
        }
        if (
          playerUpdate.state.internalCharacterId ===
          characterNameByInternalId.indexOf("Sheik")
        ) {
          return characterNameByExternalId.indexOf("Sheik");
        }
        return playerSettings.externalCharacterId;
      },
      (id) => (id === undefined ? undefined : fetchAnimations(id))
    )
  );
}
animationResources.forEach(([dataSignal], playerIndex) =>
  createEffect(() =>
    // I can't use the obvious setReplayState("animations", playerIndex,
    // dataSignal()) because it will merge into the previous animations data
    // object, essentially overwriting the previous characters animation data
    // forever
    setReplayState("animations", (animations) => {
      const newAnimations = [...animations];
      newAnimations[playerIndex] = dataSignal();
      return newAnimations;
    })
  )
);

createEffect(() => {
  if (replayState.playbackData === undefined) {
    return;
  }
  setReplayState(
    "renderDatas",
    replayState.playbackData.frames[replayState.frame].players
      .filter((playerUpdate) => playerUpdate)
      .flatMap((playerUpdate) => {
        const animations = replayState.animations[playerUpdate.playerIndex];
        if (animations === undefined) return [];
        const renderDatas = [];
        renderDatas.push(
          computeRenderData(replayState, playerUpdate, animations, false)
        );
        if (playerUpdate.nanaState != null) {
          renderDatas.push(
            computeRenderData(replayState, playerUpdate, animations, true)
          );
        }
        return renderDatas;
      })
  );
});

function computeRenderData(
  replayState: ReplayStore,
  playerUpdate: PlayerUpdate,
  animations: CharacterAnimations,
  isNana: boolean
): RenderData {
  const playerState = (playerUpdate as PlayerUpdateWithNana)[
    isNana ? "nanaState" : "state"
  ];
  const playerInputs = (playerUpdate as PlayerUpdateWithNana)[
    isNana ? "nanaInputs" : "inputs"
  ];
  const playerSettings = replayState
    .playbackData!.settings.playerSettings.filter(Boolean)
    .find((settings) => settings.playerIndex === playerUpdate.playerIndex)!;

  const startOfActionPlayerState: PlayerState = (
    getPlayerOnFrame(
      playerUpdate.playerIndex,
      getStartOfAction(playerState, replayState.playbackData!),
      replayState.playbackData!
    ) as PlayerUpdateWithNana
  )[isNana ? "nanaState" : "state"];
  const actionName = actionNameById[playerState.actionStateId];
  const characterData = actionMapByInternalId[playerState.internalCharacterId];
  const animationName =
    characterData.animationMap.get(actionName) ??
    characterData.specialsMap.get(playerState.actionStateId) ??
    actionName;
  const animationFrames = animations[animationName];
  // TODO: validate L cancels, other fractional frames, and one-indexed
  // animations. I am currently just flooring. Converts - 1 to 0 and loops for
  // Entry, Guard, etc.
  const frameIndex =
    Math.floor(Math.max(0, playerState.actionStateFrameCounter)) %
    (animationFrames?.length ?? 1);
  // To save animation file size, duplicate frames just reference earlier
  // matching frames such as "frame20".
  const animationPathOrFrameReference = animationFrames?.[frameIndex];
  const path =
    animationPathOrFrameReference !== undefined &&
    (animationPathOrFrameReference.startsWith("frame") ?? false)
      ? animationFrames?.[
          Number(animationPathOrFrameReference.slice("frame".length))
        ]
      : animationPathOrFrameReference;
  const rotation =
    animationName === "DamageFlyRoll"
      ? getDamageFlyRollRotation(replayState, playerState)
      : isSpacieUpB(playerState)
      ? getSpacieUpBRotation(replayState, playerState)
      : 0;
  // Some animations naturally turn the player around, but facingDirection
  // updates partway through the animation and incorrectly flips the
  // animation. The solution is to "fix" the facingDirection for the duration
  // of the action, as the animation expects. However upB turnarounds and
  // Jigglypuff/Kirby mid-air jumps are an exception where we need to flip
  // based on the updated state.facingDirection.
  const facingDirection = actionFollowsFacingDirection(animationName)
    ? playerState.facingDirection
    : startOfActionPlayerState.facingDirection;
  return {
    playerState,
    playerInputs,
    playerSettings,
    path,
    innerColor: getPlayerColor(
      replayState,
      playerUpdate.playerIndex,
      playerState.isNana
    ),
    outerColor:
      startOfActionPlayerState.lCancelStatus === "missed"
        ? "red"
        : playerState.hurtboxCollisionState !== "vulnerable"
        ? "blue"
        : "black",
    transforms: [
      `translate(${playerState.xPosition} ${playerState.yPosition})`,
      // TODO: rotate around true character center instead of current guessed
      // center of position+(0,8)
      `rotate(${rotation} 0 8)`,
      `scale(${characterData.scale} ${characterData.scale})`,
      `scale(${facingDirection} 1)`,
      "scale(.1 -.1) translate(-500 -500)",
    ],
    animationName,
    characterData,
  };
}

// DamageFlyRoll default rotation is (0,1), but we calculate rotation from (1,0)
// so we need to subtract 90 degrees. Quick checks:
// 0 - 90 = -90 which turns (0,1) into (1,0)
// -90 - 90 = -180 which turns (0,1) into (-1,0)
// Facing direction is handled naturally because the rotation will go the
// opposite direction (that scale happens first) and the flip of (0,1) is still
// (0, 1)
function getDamageFlyRollRotation(
  replayState: ReplayStore,
  playerState: PlayerState
): number {
  const previousState = (
    getPlayerOnFrame(
      playerState.playerIndex,
      playerState.frameNumber - 1,
      replayState.playbackData!
    ) as PlayerUpdateWithNana
  )[playerState.isNana ? "nanaState" : "state"];
  const deltaX = playerState.xPosition - previousState.xPosition;
  const deltaY = playerState.yPosition - previousState.yPosition;
  return (Math.atan2(deltaY, deltaX) * 180) / Math.PI - 90;
}

// Rotation will be whatever direction the player was holding at blastoff. The
// default rotation of the animation is (1,0), so we need to subtract 180 when
// facing left, and subtract 0 when facing right.
// Quick checks:
// 0 - 0 = 0, so (1,0) is unaltered when facing right
// 0 - 180 = -180, so (1,0) is flipped when facing left
function getSpacieUpBRotation(
  replayState: ReplayStore,
  playerState: PlayerState
): number {
  const startOfActionPlayer = getPlayerOnFrame(
    playerState.playerIndex,
    getStartOfAction(playerState, replayState.playbackData!),
    replayState.playbackData!
  );
  const joystickDegrees =
    ((startOfActionPlayer.inputs.processed.joystickY === 0 &&
    startOfActionPlayer.inputs.processed.joystickX === 0
      ? Math.PI / 2
      : Math.atan2(
          startOfActionPlayer.inputs.processed.joystickY,
          startOfActionPlayer.inputs.processed.joystickX
        )) *
      180) /
    Math.PI;
  return (
    joystickDegrees -
    ((startOfActionPlayer as PlayerUpdateWithNana)[
      playerState.isNana ? "nanaState" : "state"
    ].facingDirection === -1
      ? 180
      : 0)
  );
}

// All jumps and upBs either 1) Need to follow the current frame's
// facingDirection, or 2) Won't have facingDirection change during the action.
// In either case we can grab the facingDirection from the current frame.
function actionFollowsFacingDirection(animationName: string): boolean {
  return (
    animationName.includes("Jump") ||
    ["SpecialHi", "SpecialAirHi"].includes(animationName)
  );
}

function isSpacieUpB(playerState: PlayerState): boolean {
  const character = characterNameByInternalId[playerState.internalCharacterId];
  return (
    ["Fox", "Falco"].includes(character) &&
    [355, 356].includes(playerState.actionStateId)
  );
}

function wrapFrame(replayState: ReplayStore, frame: number): number {
  if (!replayState.playbackData) return frame;
  return (
    (frame + replayState.playbackData.frames.length) %
    replayState.playbackData.frames.length
  );
}

function wrapHighlight(replayState: ReplayStore, highlight: number): number {
  const length = Object.entries(replayState.highlights).flatMap(
    ([name, highlights]) => highlights
  ).length;
  return (highlight + length) % length;
}
