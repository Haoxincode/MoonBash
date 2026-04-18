import { afterAll } from "vite-plus/test";
import { isRecordMode, writeAllFixtures } from "./fixture-runner.js";

// Write all accumulated fixtures after all tests complete
afterAll(async () => {
  if (isRecordMode) {
    await writeAllFixtures();
  }
});
