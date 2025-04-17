import { build } from "esbuild";
import { solidPlugin } from "esbuild-plugin-solid";

await build({
  entryPoints: ["src/index.ts", "src/worker/worker.ts"],
  bundle: true,
  outdir: "../priv/static/assets/",
  minify: true,
  loader: {
    ".svg": "dataurl",
    ".css": "text"
  },
  logLevel: "info",
  plugins: [solidPlugin()],
}).catch(() => process.exit(1));
