import { build, context } from "esbuild";
import { solidPlugin } from "esbuild-plugin-solid";

import fs from "node:fs";
import path from "node:path";
import child_process from "node:child_process"
import util from "node:util";

const exec = util.promisify(child_process.exec);

const buildCssPlugin = {
  name: 'buildCssPlugin',
  setup(build) {
    build.onStart(async () => {
      const cssFiles = fs.readdirSync("src/css");
      const execPromises = [];
      for (const file of cssFiles) {
        console.log(`Building ${file}...`);
        execPromises.push(exec(`npx tailwindcss -c tailwind.config.js -i src/css/${file} -o build/css/${file} --minify`));
      }
      await Promise.all(execPromises);
    });

    build.onResolve({ filter: /\.css/ }, args => {
      const cssPath = path.dirname(args.path);
      const fileName = path.basename(args.path);
      return { path: path.join(args.resolveDir, cssPath, '../../build/css', fileName) }
    });

    build.onEnd(() => {
      fs.rmSync("build", { recursive: true, force: true });
    });
  },
}

const buildOptions = {
  entryPoints: ["src/index.tsx", "src/worker/worker.ts"],
  bundle: true,
  // outdir: "dist/",
  outdir: "../../../priv/static/assets",
  minify: true,
  loader: {
    ".svg": "dataurl",
    ".css": "text"
  },
  logLevel: "info",
  plugins: [solidPlugin(), buildCssPlugin],
}

if (process.argv.length > 2 && ["--watch", "-w"].includes(process.argv[2])) {
  const buildContext = await context(buildOptions)
  await buildContext.watch();
} else {
  await build(buildOptions);
}
