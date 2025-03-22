import { defineConfig } from "vite";
import solidPlugin from "vite-plugin-solid";
import viteTsconfigPaths from "vite-tsconfig-paths";

/*
export default defineConfig({
  assetsInclude: [/.*zip$/, /.*ttf$/],
  plugins: [solidPlugin(), viteTsconfigPaths()],
  resolve: {
    conditions: ["browser"],
  },
});
*/

export default defineConfig(({ command }: any) => {
  const isDev = command !== "build";
  if (isDev) {
    // Terminate the watcher when Phoenix quits
    process.stdin.on("close", () => {
      process.exit(0);
    });

    process.stdin.resume();
  }

  return {
    assetsInclude: [/.*zip$/, /.*ttf$/],
    publicDir: "static",
    plugins: [solidPlugin(), viteTsconfigPaths()],
    build: {
      target: "esnext", // build for recent browsers
      outDir: "../priv/static", // emit assets to priv/static
      emptyOutDir: true,
      sourcemap: isDev, // enable source map in dev build
      manifest: false, // do not generate manifest.json
      rollupOptions: {
        input: {
          main: "./src/root.tsx"
        },
        output: {
          entryFileNames: "assets/[name].js", // remove hash
          chunkFileNames: "assets/[name].js",
          assetFileNames: "assets/[name][extname]"
        }
      }
    }
  };
});
