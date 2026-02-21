import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const rootDir = dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  resolve: {
    alias: [
      {
        find: "../../index.js",
        replacement: resolve(rootDir, "src/wrapper/index.ts"),
      },
      {
        find: /^fast-check$/,
        replacement: resolve(rootDir, "src/wrapper/fast-check-compat.ts"),
      },
      {
        find: /^fast-check-real$/,
        replacement: resolve(rootDir, "node_modules/fast-check/lib/fast-check.js"),
      },
    ],
  },
  test: {
    include: ["tests/**/*.test.ts"],
    setupFiles: ["tests/comparison/vitest.setup.ts"],
    testTimeout: 30000,
  },
});
