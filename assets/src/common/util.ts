import { unzipSync } from "fflate";
import colors from "tailwindcss/colors";
import { PlaybackStore } from "~/common/types";

export async function filterFiles(files: File[]): Promise<File[]> {
  const slpFiles = files.filter((file) => file.name.endsWith(".slp"));
  const zipFiles = files.filter((file) => file.name.endsWith(".zip"));
  const blobsFromZips = (await Promise.all(zipFiles.map(unzip)))
    .flat()
    .filter((file) => file.name.endsWith(".slp"));
  return [...slpFiles, ...blobsFromZips];
}

export async function unzip(zipFile: File): Promise<File[]> {
  const fileBuffers = unzipSync(new Uint8Array(await zipFile.arrayBuffer()));
  return Object.entries(fileBuffers).map(
    ([name, buffer]) => new File([buffer], name)
  );
}

export function getPlayerColor(
  playbackStore: PlaybackStore,
  playerIndex: number,
  isNana: boolean
): string {
  if (playbackStore.playbackData!.settings.isTeams) {
    const settings =
    playbackStore.playbackData!.settings.playerSettings[playerIndex];
    return [
      [colors.red["800"], colors.red["600"]],
      [colors.green["800"], colors.green["600"]],
      [colors.blue["800"], colors.blue["600"]],
    ][settings.teamId][isNana ? 1 : settings.teamShade];
  }
  return [
    [colors.red["700"], colors.red["600"]],
    [colors.blue["700"], colors.blue["600"]],
    [colors.yellow["500"], colors.yellow["400"]],
    [colors.green["700"], colors.green["600"]],
  ][playerIndex][isNana ? 1 : 0];
}
