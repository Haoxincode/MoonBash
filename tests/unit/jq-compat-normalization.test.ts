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

  it("provides compatibility aliases for missing jq builtins", async () => {
    const bash = new Bash();

    const arrays = await bash.exec("echo '[1,{}]' | jq -c '[.[]|arrays]'");
    const debug = await bash.exec("echo '1' | jq -c 'debug'");
    const fabs = await bash.exec("echo '[-0,0,-10,-1.1]' | jq -c 'map(fabs)'");
    const builtins = await bash.exec("echo 'null' | jq -c 'builtins|length > 10'");

    expect(arrays.exitCode).toBe(0);
    expect(arrays.stdout).toBe("[]\n");

    expect(debug.exitCode).toBe(0);
    expect(debug.stdout).toBe("1\n");

    expect(fabs.exitCode).toBe(0);
    expect(fabs.stdout).toBe("[0,0,10,1.1]\n");

    expect(builtins.exitCode).toBe(0);
    expect(builtins.stdout).toBe("true\n");
  });

  it("supports IN compatibility for range-based forms", async () => {
    const bash = new Bash();

    const unary = await bash.exec("echo 'null' | jq -c 'range(5;10)|IN(range(10))'");
    const binary = await bash.exec("echo 'null' | jq -c 'IN(range(5;20); range(10))'");

    expect(unary.exitCode).toBe(0);
    expect(unary.stdout).toBe("true\ntrue\ntrue\ntrue\ntrue\n");

    expect(binary.exitCode).toBe(0);
    expect(binary.stdout).toBe("true\n");
  });
});
