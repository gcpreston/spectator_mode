import { render } from "solid-js/web";
import { MiniApp } from "~/components/MiniApp";

const root = document.querySelector("#root");
if (root !== null) {
  render(MiniApp, root);
}
