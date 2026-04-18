import { defineConfig } from "vite-plus";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(rootDir, "examples/website");

export default defineConfig({
  root: websiteRoot,
  base: "./",
  publicDir: false,
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: true,
    target: "es2022",
  },
  server: {
    port: 4173,
    strictPort: true,
    fs: {
      allow: [rootDir],
    },
  },
  preview: {
    port: 4173,
    strictPort: true,
  },
});
