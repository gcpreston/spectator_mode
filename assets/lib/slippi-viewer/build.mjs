import { build, context } from "esbuild";
import { solidPlugin } from "esbuild-plugin-solid";

import fs from "node:fs";
import path from "node:path";
import child_process from "node:child_process"
import util from "node:util";

const exec = util.promisify(child_process.exec);

// Because a web component is being created, it cannot be styled by a CSS file
// which will be included somewhere such as an index.html. Instead, the styles
// must be directly added to the component within a <styles> tag, which means
// importing them as text.
// Because Tailwind is being used, meaning index.css must be compiled, and
// recompiled to only include the necessary classes, this is added to the build
// pipeline as a plugin here, to generate/minify all CSS before it is imported.

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
      const fileName = path.basename(args.path);
      return { path: path.join(import.meta.dirname, 'build/css', fileName) }
    });

    build.onEnd(() => {
      fs.rmSync("build", { recursive: true, force: true });
    });
  },
}

const buildOptions = {
  entryPoints: ["src/index.tsx", "src/worker/worker.ts"],
  bundle: true,
  outdir: "dist/",
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
