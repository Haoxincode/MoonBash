import { describe, expect, it } from "vitest";
import { Bash } from "./Bash.js";

describe("jq memory safety", () => {
  it("allows huge repeat when input string is empty", async () => {
    const bash = new Bash();

    const result = await bash.exec("echo '\"\"' | jq -c '. * 1000000000'");

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe('""\n');
  });

  it("fails fast for huge repeat on non-empty strings", async () => {
    const bash = new Bash();

    const result = await bash.exec("echo '\"abc\"' | jq -c '. * 1000000000'");

    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain("Repeat string result too long");
  });
});
