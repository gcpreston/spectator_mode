import {
  PlayerState,
  PlayerUpdate,
  PlayerUpdateWithNana,
  NonReactiveState
} from "~/common/types";

export function getStartOfAction(
  playerState: PlayerState,
  nonReactiveState: NonReactiveState
): number {
  let earliestStateOfAction = (
    getPlayerOnFrame(
      playerState.playerIndex,
      playerState.frameNumber,
      nonReactiveState
    ) as PlayerUpdateWithNana
  )[playerState.isNana ? "nanaState" : "state"];
  while (true) {
    const testEarlierState = getPlayerOnFrame(
      playerState.playerIndex,
      earliestStateOfAction.frameNumber - 1,
      nonReactiveState
    )?.[playerState.isNana ? "nanaState" : "state"];
    if (
      testEarlierState === undefined ||
      testEarlierState.actionStateId !== earliestStateOfAction.actionStateId ||
      testEarlierState.actionStateFrameCounter >
        earliestStateOfAction.actionStateFrameCounter
    ) {
      return earliestStateOfAction.frameNumber;
    }
    earliestStateOfAction = testEarlierState;
  }
}

export function getPlayerOnFrame(
  playerIndex: number,
  frameNumber: number,
  nonReactiveState: NonReactiveState
): PlayerUpdate {
  return nonReactiveState.gameFrames[frameNumber]?.players[playerIndex];
}
