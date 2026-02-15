import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    setupFiles: ["tests/comparison/vitest.setup.ts"],
    testTimeout: 30000,
  },
});
