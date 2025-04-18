import "@thisbeyond/solid-select/style.css";
import { onCleanup, Show } from "solid-js";
import { Viewer } from "~/components/viewer/Viewer";
import { fetchAnimations } from "~/viewer/animationCache";
import "~/state/spectateStore";
import { bridgeId, setBridgeId } from "~/state/spectateStore";

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
      <Show when={Boolean(bridgeId())}>
        <Viewer />
      </Show>
    </div>
  );
}
