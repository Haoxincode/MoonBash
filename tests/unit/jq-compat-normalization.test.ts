import { describe, expect, it } from "vitest";
import { Bash } from "./Bash.js";

describe("jq compatibility normalization", () => {
  it("accepts UTF-8 BOM prefixed JSON input", async () => {
    const bash = new Bash();
    const bom = "\uFEFF";

    const result = await bash.exec(`echo '${bom}"byte order mark"' | jq -c '.'`);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("\"byte order mark\"\n");
  });

  it("normalizes quoted member chain access", async () => {
    const bash = new Bash();

    const result = await bash.exec(`echo '{"foo":{"bar":20}}' | jq -c '."foo"."bar"'`);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("20\n");
  });

  it("normalizes bracket-quoted member access", async () => {
    const bash = new Bash();

    const result = await bash.exec(`echo '{"foo":{"bar":42}}' | jq -c '.[\"foo\"].bar'`);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("42\n");
  });

  it("normalizes binary minus without surrounding spaces", async () => {
    const bash = new Bash();

    const result = await bash.exec("echo 'null' | jq -c '2-1'");

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("1\n");
  });
});
