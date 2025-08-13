// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import "@gcpreston/slippi-viewer"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

function spectateStream(streamId) {
  const viewer = document.querySelector("#viewer");
  const wsProtocol = document.location.protocol === "http:" ? "ws:" : "wss:";

  if (!streamId) {
    viewer.clear();
  } else {
    // can't just use relaative path because connection is made from a blob file
    viewer.spectate(`${wsProtocol}//${document.location.host}/viewer_socket/websocket?stream_id=${streamId}`);
  }
}

const StreamIdHook = {
  mounted() {
    const streamId = this.el.getAttribute("streamId");
    spectateStream(streamId);
  },

  updated() {
    const streamId = this.el.getAttribute("bridstreamIdgeid");
    spectateStream(streamId);
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 8000,
  params: {_csrf_token: csrfToken},
  hooks: {StreamIdHook}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
