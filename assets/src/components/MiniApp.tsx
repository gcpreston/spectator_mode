import "@thisbeyond/solid-select/style.css";
import { Viewer } from "~/components/viewer/Viewer";
import { fetchAnimations } from "~/viewer/animationCache";
import "~/state/spectateStore";

export function MiniApp({ bridgeId, postWorker }: { bridgeId: string }) {
  // Get started fetching the most popular characters
  void fetchAnimations(20); // Falco
  void fetchAnimations(2); // Fox
  void fetchAnimations(0); // Falcon
  void fetchAnimations(9); // Marth

  return (
    <div class="flex max-h-screen flex-grow flex-col gap-2 pt-2 pr-4 pl-4 lg:pl-0">
      <button onClick={postWorker}>Test worker</button>
      <Viewer />
    </div>
  );
}
