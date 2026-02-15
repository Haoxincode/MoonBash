/**
 * MoonBash - Zero-dependency POSIX Shell Sandbox
 *
 * API-compatible with vercel-labs/just-bash.
 * Compiled from MoonBit to pure JavaScript (no WASM).
 */

import type { ExecResult, BashOptions, FileSystem } from "./types";
import { spawnSync } from "node:child_process";

export type { ExecResult, BashOptions, FileSystem } from "./types";

// Import the compiled MoonBit engine
// @ts-ignore - generated file has no type declarations
import { execute_with_state as mbExecuteWithState } from "../_build/js/debug/build/lib/entry/entry.js";

type HostToolRunner = (
  tool: string,
  argsBlob: string,
  stdinContent: string,
  cwd: string,
) => string;

function installHostToolRunner(): void {
  const g = globalThis as Record<string, unknown>;
  if (typeof g.__moonbash_run_host_tool === "function") {
    return;
  }

  const runner: HostToolRunner = (
    tool: string,
    argsBlob: string,
    stdinContent: string,
  ): string => {
    let args: string[] = [];
    if (argsBlob.length > 0) {
      try {
        const parsed = JSON.parse(argsBlob);
        if (Array.isArray(parsed)) {
          args = parsed.filter((v): v is string => typeof v === "string");
        }
      } catch {
        args = [];
      }
    }
    try {
      const child = spawnSync(tool, args, {
        input: stdinContent,
        encoding: "utf-8",
        cwd: process.cwd(),
        env: process.env,
        maxBuffer: 10 * 1024 * 1024,
      });

      const stdout = typeof child.stdout === "string" ? child.stdout : "";
      const stderr = typeof child.stderr === "string" ? child.stderr : "";
      const exitCode = typeof child.status === "number" ? child.status : 1;
      return JSON.stringify({
        ok: true,
        stdout,
        stderr,
        exitCode,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : String(error);
      return JSON.stringify({
        ok: true,
        stdout: "",
        stderr: `${tool}: ${message}\n`,
        exitCode: 1,
      });
    }
  };

  g.__moonbash_run_host_tool = runner as unknown;
}

installHostToolRunner();

interface StateExecResult extends ExecResult {
  files?: Record<string, string>;
  dirs?: Record<string, string>;
  links?: Record<string, string>;
}

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
  private files: Record<string, string>;
  private dirs: Record<string, string>;
  private links: Record<string, string>;

  constructor(options: BashOptions = {}) {
    this.options = options;
    this.files = { ...(options.files || {}) };
    this.dirs = {};
    this.links = {};
    for (const filePath of Object.keys(this.files)) {
      this.addParentDirs(filePath);
    }
  }

  private normalizePath(inputPath: string): string {
    if (inputPath.startsWith("/")) {
      return inputPath;
    }
    const cwd = this.getCwd();
    if (cwd === "/") {
      return `/${inputPath}`;
    }
    return `${cwd}/${inputPath}`;
  }

  private addParentDirs(filePath: string): void {
    if (!filePath.startsWith("/")) return;
    const parts = filePath.split("/").filter(Boolean);
    let current = "";
    for (let i = 0; i < parts.length - 1; i += 1) {
      current += `/${parts[i]}`;
      this.dirs[current] = "1";
    }
  }

  private applyState(result: StateExecResult): void {
    if (result.files && typeof result.files === "object") {
      this.files = result.files;
    }
    if (result.dirs && typeof result.dirs === "object") {
      this.dirs = result.dirs;
    }
    if (result.links && typeof result.links === "object") {
      this.links = result.links;
    }
  }

  /**
   * Execute a bash script in the sandbox.
   * Returns stdout, stderr, and exit code.
   */
  async exec(script: string): Promise<ExecResult> {
    const envJson = JSON.stringify(this.options.env || {});
    const filesJson = JSON.stringify(this.files);
    const dirsJson = JSON.stringify(this.dirs);
    const linksJson = JSON.stringify(this.links);
    const cwd = this.options.cwd || "/home/user";

    const jsonResult = mbExecuteWithState(
      script,
      envJson,
      filesJson,
      dirsJson,
      linksJson,
      cwd,
    );
    const parsed = JSON.parse(jsonResult) as StateExecResult;
    this.applyState(parsed);
    return parsed;
  }

  async readFile(path: string): Promise<string> {
    const normalized = this.normalizePath(path);
    if (Object.prototype.hasOwnProperty.call(this.files, normalized)) {
      return this.files[normalized];
    }
    throw new Error(`No such file: ${normalized}`);
  }

  async writeFile(path: string, content: string): Promise<void> {
    const normalized = this.normalizePath(path);
    this.files[normalized] = content;
    this.addParentDirs(normalized);
  }

  getCwd(): string {
    if (this.options.cwd && this.options.cwd.length > 0) {
      return this.options.cwd;
    }
    return "/home/user";
  }

  getEnv(): Record<string, string> {
    return { ...(this.options.env || {}) };
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
