/**
 * MoonBash - Zero-dependency POSIX Shell Sandbox
 *
 * API-compatible with vercel-labs/just-bash.
 * Compiled from MoonBit to pure JavaScript (no WASM).
 */

import type { ExecResult, BashOptions, FileSystem } from "./types";

export type { ExecResult, BashOptions, FileSystem } from "./types";

/**
 * Main entry point for executing bash commands in a sandboxed environment.
 *
 * @example
 * ```ts
 * const bash = new Bash();
 * const result = await bash.exec('echo "hello world"');
 * console.log(result.stdout); // "hello world\n"
 * ```
 */
export class Bash {
  private options: BashOptions;

  constructor(options: BashOptions = {}) {
    this.options = options;
  }

  /**
   * Execute a bash script in the sandbox.
   * Returns stdout, stderr, and exit code.
   */
  async exec(script: string): Promise<ExecResult> {
    // TODO: Bridge to MoonBit compiled engine
    // This is a stub that will be replaced when the MoonBit->JS build pipeline is set up.
    void script;
    return {
      stdout: "",
      stderr: "moonbash: engine not yet compiled\n",
      exitCode: 1,
    };
  }

  /**
   * Get the virtual filesystem interface.
   */
  getFs(): FileSystem {
    // TODO: Bridge to MoonBit InMemoryFs
    throw new Error("moonbash: engine not yet compiled");
  }
}

/**
 * Convenience function to execute a bash command.
 * Creates a temporary Bash instance with the given options.
 *
 * @example
 * ```ts
 * const result = await exec('echo hello', { env: { USER: 'agent' } });
 * ```
 */
export async function exec(
  script: string,
  options: BashOptions = {}
): Promise<ExecResult> {
  const bash = new Bash(options);
  return bash.exec(script);
}

/**
 * Sandbox class - provides isolated execution environments.
 * API-compatible with just-bash Sandbox.
 */
export class Sandbox {
  private bash: Bash;

  constructor(options: BashOptions = {}) {
    this.bash = new Bash(options);
  }

  /**
   * Execute a script in this sandbox.
   */
  async exec(script: string): Promise<ExecResult> {
    return this.bash.exec(script);
  }

  /**
   * Get the virtual filesystem for this sandbox.
   */
  getFs(): FileSystem {
    return this.bash.getFs();
  }
}
