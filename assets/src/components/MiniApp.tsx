import "@thisbeyond/solid-select/style.css";
import { onCleanup, Show } from "solid-js";
import { Viewer } from "~/components/viewer/Viewer";
import { fetchAnimations } from "~/viewer/animationCache";
import "~/state/spectateStore";
import { bridgeId, setBridgeId } from "~/state/spectateStore";
/**
 * THE VISION FOR PORTABLE VIEWER
 * - solid-element provides the ability to create a web component custom
 *   element from a solidjs component alongside rollup/babel
 *   * https://giancarlobuomprisco.com/solid/building-widgets-solidjs-web-components
 * - Custom elements can have observed attributes
 *   * https://developer.mozilla.org/en-US/docs/Web/API/Web_components/Using_custom_elements#custom_element_lifecycle_callbacks
 * - Custom elements can have custom methods
 *   * https://stackoverflow.com/a/55480022
 *
 * - Create a custom element with the following API:
 *   * const viewer = document.querySelector("slippi-viewer");
 *   * viewer.setReplay(replayData: ArrayBuffer): void
 *   * viewer.setSpectate(wsUrl: string, initialEvents?: { eventPayloads: ArrayBuffer, gameStart: ArrayBuffer }): void
 *     - expects initialEvents if tuning in mid-game
 *     - spectator_mode can provide a wrapper component which just takes
 *       bridgeid as an observed attribute
 */

export function MiniApp() {
  // Get started fetching the most popular characters
  void fetchAnimations(20); // Falco
  void fetchAnimations(2); // Fox
  void fetchAnimations(0); // Falcon
  void fetchAnimations(9); // Marth

  // Observe bridge ID, since this is set by Phoenix
  const target = document.querySelector('#bridge-id-target');
  const initialBridgeId = target!.getAttribute("bridgeid");

  if (initialBridgeId) {
    setBridgeId(initialBridgeId);
  }

  const observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(mutation) {
      if (mutation.attributeName) {
        const newBridgeId = target!.getAttribute(mutation.attributeName);
        setBridgeId(newBridgeId);
      }
    });
  });

  if (target) {
    observer.observe(target, { attributes: true });
  }

  onCleanup(() => {
    observer.disconnect();
  });

  return (
    <div class="flex max-h-screen flex-grow flex-col gap-2 pt-2 pr-4 pl-4 lg:pl-0">
      <Show
        when={Boolean(bridgeId())}
        fallback={<div class="text-center italic">Click on a stream to get started</div>}
      >
        <Viewer />
      </Show>
    </div>
  );
}
