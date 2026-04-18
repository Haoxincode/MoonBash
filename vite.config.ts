import { defineConfig } from "vite-plus";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

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
  pack: {
    entry: ["src/wrapper/index.ts"],
    dts: true,
    format: ["esm"],
    sourcemap: true,
  },
  fmt: {
    ignorePatterns: [
      ".agents/**",
      ".tmp/**",
      "docs/**",
      "examples/**",
      "tests/**",
      "src/.mooncakes/**",
      "src/_build/**",
      "src/lib/**",
      "src/website/**",
      "AGENTS.md",
      "CLAUDE.md",
      "pnpm-workspace.yaml",
    ],
  },
  lint: {
    ignorePatterns: [
      ".agents/**",
      ".tmp/**",
      "docs/**",
      "examples/**",
      "tests/**",
      "src/.mooncakes/**",
      "src/_build/**",
      "src/lib/**",
      "src/website/**",
    ],
    options: {
      typeAware: true,
      typeCheck: true,
    },
  },
});
