/**
 * MoonBash - Zero-dependency POSIX Shell Sandbox
 *
 * API-compatible with vercel-labs/just-bash.
 * Compiled from MoonBit to pure JavaScript (no WASM).
 */

import type { ExecResult, BashOptions, FileSystem } from "./types";

export type { ExecResult, BashOptions, FileSystem } from "./types";

// Import the compiled MoonBit engine
// @ts-ignore - generated file has no type declarations
import { execute as mbExecute, execute_with_fs as mbExecuteWithFs } from "../_build/js/debug/build/lib/entry/entry.js";

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
    const hasFs = this.options.files && Object.keys(this.options.files).length > 0;
    const hasEnv = this.options.env && Object.keys(this.options.env).length > 0;
    const hasCwd = this.options.cwd && this.options.cwd.length > 0;

    let jsonResult: string;

    if (hasFs || hasEnv || hasCwd) {
      const envJson = JSON.stringify(this.options.env || {});
      const filesJson = JSON.stringify(this.options.files || {});
      const cwd = this.options.cwd || "/home/user";
      jsonResult = mbExecuteWithFs(script, envJson, filesJson, cwd);
    } else {
      jsonResult = mbExecute(script);
    }

    return JSON.parse(jsonResult) as ExecResult;
  }

  /**
   * Get the virtual filesystem interface.
   * Note: Currently not implemented - filesystem is internal to execution.
   */
  getFs(): FileSystem {
    throw new Error("moonbash: getFs() is not yet supported. Use the 'files' option in BashOptions instead.");
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
