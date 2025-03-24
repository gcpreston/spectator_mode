import createRAF, { targetFPS } from "@solid-primitives/raf";
import { batch, createEffect, createResource, createRoot } from "solid-js";
import { createStore } from "solid-js/store";
import { Socket } from "phoenix";
import { createToast } from "~/components/common/toaster";
import {
  actionNameById,
  characterNameByExternalId,
  characterNameByInternalId,
} from "~/common/ids";
import {
  Frame,
  PlayerState,
  PlayerUpdate,
  PlayerUpdateWithNana,
  SpectateData,
  RenderData,
  SpectateStore,
  GameEvent,
  PreFrameUpdateEvent,
  FrameStartEvent,
  PostFrameUpdateEvent,
  GameEndEvent,
  ItemUpdateEvent,
  GameStartEvent,
  CommandPayloadSizes,
} from "~/common/types";
import { queries } from "~/search/queries";
import { CharacterAnimations, fetchAnimations } from "~/viewer/animationCache";
import { actionMapByInternalId } from "~/viewer/characters";
import { getPlayerOnFrame, getStartOfAction } from "~/viewer/viewerUtil";
import { getPlayerColor } from "~/common/util";
import { parsePacket } from "~/parser/liveParser";

export const defaultSpectateStoreState: SpectateStore = {
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

  packetBuffer: [],
};

const [replayState, setReplayState] = createStore<SpectateStore>(
  defaultSpectateStoreState
);

export const spectateStore = replayState;

// Highlight code removed

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
  running() ? pause() : start();
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

export function jumpToLive(): void {
  setReplayState("frame", replayState.playbackData!.frames.length - 2);
}

export function adjust(delta: number): void {
  // TODO: Computed frame count signal
  setReplayState("frame", (f) =>
    Math.min(f + delta, replayState.playbackData!.frames.length - 2));
}

// TODO: Figure out how to put this in createRoot
const [running, start, stop] = createRAF(
  targetFPS(
    () => {
      const tryFrame = replayState.frame + replayState.framesPerTick;
      if (tryFrame < replayState.playbackData!.frames.length - 2) {
        setReplayState("frame", tryFrame);
      }
    },
    () => replayState.fps
  )
);
createEffect(() => setReplayState("running", running()));

// on initial load: connect to websocket, define callbacks
//   - initialize empty SpectateStore
//   - expect first packets first
//   - parseFrame for subsequent packets; add to SpectateStore
//   - replay running effect should depend on spectateStore.frames (run the last frame always?)

// ------------------------------------
// TODO: Error handling

export function connectWS(): void {
  console.log('connection attempt');
  const PHOENIX_URL = '/socket';
  const socket = new Socket(PHOENIX_URL);

  // TODO: Move to createRoot
  /*
  createEffect(() => {
    ws.onmessage = ({ data }: { data: Blob }) => {
      setReplayState("packetBuffer", [...replayState.packetBuffer, data]);
    }
  });
  */

  socket.connect();
  console.log('after socket connect', socket);

  // Now that you are connected, you can join channels with a topic:
  const bridgeId = "08740a33-1cfc-4daa-9a86-dafdbba3e5ec";
  const phoenixChannel = socket.channel("view:" + bridgeId);
  console.log('channel', phoenixChannel);
  phoenixChannel.join()
    .receive("ok", (resp: any) => {
      console.log("Joined successfully", resp);

      createToast({
        title: `Connection success`,
        duration: 2000,
        render: () => (
          <div>Streaming from {PHOENIX_URL}</div>
        ),
        placement: "top-end",
      });

      phoenixChannel.on("game_data", (payload: ArrayBuffer) => {
        setReplayState("packetBuffer", [...replayState.packetBuffer, payload]);
      });
    })
    .receive("error", (resp: any) => {
      console.log('WebSocket error:', resp);

      createToast({
        title: `WebSocket connection error`,
        duration: 2000,
        render: () => (
          <div>Failed to connect to {PHOENIX_URL}</div>
        ),
        placement: "top-end",
      });
    });
}

export function closeWS(): void {
  /* TODO: Switch for phoenix
  const maybeWs = replayState.ws;
  if (maybeWs) {
    maybeWs.close();
  }
  */
}

declare global {
  var payloadSizes: CommandPayloadSizes | undefined;
}

globalThis.payloadSizes = undefined;

function setReplayStateFromGameEvent(gameEvent: GameEvent): void {
  switch (gameEvent.type) {
    case "event_payloads":
      handleEventPayloadsEvent();
      break;
    case "game_start":
      handleGameStartEvent(gameEvent.data);
      break;
    case "pre_frame_update":
      handlePreFrameUpdateEvent(gameEvent.data);
      break;
    case "post_frame_update":
      handlePostFrameUpdateEvent(gameEvent.data);
      break;
    case "game_end":
      handleGameEndEvent(gameEvent.data);
      break;
    case "frame_start":
      handleFrameStartEvent(gameEvent.data);
      break;
    case "item_update":
      handleItemUpdateEvent(gameEvent.data);
      break;
  }
}

function handleEventPayloadsEvent() {
  const initialPlaybackData: SpectateData = {
    // @ts-expect-error: settings will be populated on game start
    settings: undefined,
    frames: [],
    ending: undefined
  }
  // New game, reset spectate data
  // TODO: Why does frame get mutated in defaultSpectateStoreState?
  setReplayState({ ...defaultSpectateStoreState, playbackData: initialPlaybackData, frame: 0 });
}

function handleGameStartEvent(settings: GameStartEvent) {
  setReplayState("playbackData", { ...replayState.playbackData!, settings });
  start();
}

function initFrameIfNeeded(frames: Frame[], frameNumber: number): Frame {
  if (frames[frameNumber] === undefined) {
    // @ts-expect-error: randomSeed will be populated later if found.
    return {
      frameNumber: frameNumber,
      players: [],
      items: [],
    };
  } else {
    return frames[frameNumber];
  }
}

function initPlayerIfNeeded(
  frame: Frame,
  playerIndex: number
): Frame {
  if (frame.players[playerIndex] !== undefined) return frame;

  const players = frame.players.slice();
  // @ts-expect-error: state and inputs will be populated later.
  players[playerIndex] = {
    frameNumber: frame.frameNumber,
    playerIndex: playerIndex,
  };
  return { ...frame, players };
}

function isRollbackFromFrameUpdate(frames: Frame[], frameNumber: number): boolean {
  const maybeFrame = frames[frameNumber];
  return Boolean(maybeFrame && maybeFrame.players);
}

function handlePreFrameUpdateEvent(playerInputs: PreFrameUpdateEvent): void {
  if (isRollbackFromFrameUpdate(replayState.playbackData!.frames, playerInputs.frameNumber)) {
    // Cut off stale frames, and roll back to the new playback point.
    // Relies on updates being batched, as otherwise the frame would
    // not yet be finished at this point.
    const frames = replayState.playbackData!.frames.slice(0, playerInputs.frameNumber + 1);
    setReplayState("playbackData", { ...replayState.playbackData!, frames });
    setReplayState("frame", playerInputs.frameNumber);
  }

  // Some older versions don't have the Frame Start Event so we have to
  // potentially initialize the frame in both places.
  let frame = initFrameIfNeeded(replayState.playbackData!.frames, playerInputs.frameNumber);
  frame = initPlayerIfNeeded(
    frame,
    playerInputs.playerIndex
  );
  if (playerInputs.isNana) {
    const players = frame.players.slice();
    const player: PlayerUpdate = { ...frame.players[playerInputs.playerIndex], nanaInputs: playerInputs };
    players[player.playerIndex] = player;
    frame = { ...frame, players };
    const frames = replayState.playbackData!.frames.slice();
    frames[playerInputs.frameNumber] = frame;
    setReplayState("playbackData", { ...replayState.playbackData!, frames });
  } else {
    const players = frame.players.slice();
    const player: PlayerUpdate = { ...frame.players[playerInputs.playerIndex], inputs: playerInputs };
    players[player.playerIndex] = player;
    frame = { ...frame, players };
    const frames = replayState.playbackData!.frames.slice();
    frames[playerInputs.frameNumber] = frame;
    setReplayState("playbackData", { ...replayState.playbackData!, frames });
  }
}

function handlePostFrameUpdateEvent(playerState: PostFrameUpdateEvent): void {
  if (isRollbackFromFrameUpdate(replayState.playbackData!.frames, playerState.frameNumber)) {
    // Cut off stale frames, and roll back to the new playback point.
    // Relies on updates being batched, as otherwise the frame would
    // not yet be finished at this point.
    const frames = replayState.playbackData!.frames.slice(0, playerState.frameNumber + 1);
    setReplayState("playbackData", { ...replayState.playbackData!, frames });
    setReplayState("frame", playerState.frameNumber);
  }

  const frame = replayState.playbackData!.frames[playerState.frameNumber];
  if (playerState.isNana) {
    const players = frame.players.slice();
    const player: PlayerUpdate = { ...players[playerState.playerIndex], nanaState: playerState };
    players[player.playerIndex] = player;

    const frames = replayState.playbackData!.frames.slice();
    frames[playerState.frameNumber] = { ...frame, players };
    setReplayState("playbackData", { ...replayState.playbackData!, frames });
  } else {
    const players = frame.players.slice();
    const player: PlayerUpdate = { ...players[playerState.playerIndex], state: playerState };
    players[player.playerIndex] = player;

    const frames = replayState.playbackData!.frames.slice();
    frames[playerState.frameNumber] = { ...frame, players };
    setReplayState("playbackData", { ...replayState.playbackData!, frames });
  }
}

function handleGameEndEvent(gameEnding: GameEndEvent) {
  setReplayState("playbackData", { ...replayState.playbackData!, ending: gameEnding });
}

function handleFrameStartEvent(frameStart: FrameStartEvent): void {
  const { frameNumber, randomSeed } = frameStart;
  const frame = initFrameIfNeeded(replayState.playbackData!.frames, frameNumber);
  // @ts-ignore not sure what to do about this
  frame.randomSeed = randomSeed;
  const frames = replayState.playbackData!.frames.slice();
  frames[frame.frameNumber] = frame;
  setReplayState("playbackData", { ...replayState.playbackData!, frames });
}

function handleItemUpdateEvent(itemUpdate: ItemUpdateEvent): void {
  const frames = replayState.playbackData!.frames.slice();
  let frame = frames[itemUpdate.frameNumber];
  const items = frame.items.slice();
  items.push(itemUpdate);
  frame = { ...frame, items };
  frames[itemUpdate.frameNumber] = frame;
  setReplayState("playbackData", { ...replayState.playbackData!, frames });
}

createRoot(() => {
  createEffect(() => {
    // TODO: This could be some kind of forEach instead maybe
    if (replayState.packetBuffer.length > 0) {
      const buf = replayState.packetBuffer[0];
      const bufferRest = replayState.packetBuffer.slice(1);
      setReplayState("packetBuffer", bufferRest);

      const gameEvents = parsePacket(
        new Uint8Array(buf),
        replayState.playbackData
      );

      batch(() => {
        gameEvents.forEach((gameEvent) => {
          setReplayStateFromGameEvent(gameEvent)
        });
      });
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
          // TODO: Remove this one when the code isn't awful lol
          if (replay.settings === undefined) {
            return undefined
          }
          const playerSettings = replay.settings.playerSettings[playerIndex];
          if (playerSettings === undefined) {
            return undefined;
          }
          if (replay.frames[replayState.frame] === undefined) {
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
      replayState.playbackData.frames.length <= replayState.frame ? [] : replayState.playbackData.frames[replayState.frame].players
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
});

function computeRenderData(
  replayState: SpectateStore,
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
  replayState: SpectateStore,
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
  replayState: SpectateStore,
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

function wrapFrame(replayState: SpectateStore, frame: number): number {
  if (!replayState.playbackData) return frame;
  return (
    (frame + replayState.playbackData.frames.length) %
    replayState.playbackData.frames.length
  );
}

function wrapHighlight(replayState: SpectateStore, highlight: number): number {
  const length = Object.entries(replayState.highlights).flatMap(
    ([name, highlights]) => highlights
  ).length;
  return (highlight + length) % length;
}
