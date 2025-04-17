import { build } from "esbuild";
import { solidPlugin } from "esbuild-plugin-solid";

await build({
  entryPoints: ["src/index.ts"],
  bundle: true,
  outfile: "../priv/static/assets/main.js",
  minify: true,
  loader: {
    ".svg": "dataurl",
    ".css": "text"
  },
  logLevel: "info",
  plugins: [solidPlugin()],
}).catch(() => process.exit(1));
