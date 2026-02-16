/**
 * MoonBash - Zero-dependency POSIX Shell Sandbox
 *
 * API-compatible with vercel-labs/just-bash.
 * Compiled from MoonBit to pure JavaScript (no WASM).
 */

import type {
  ExecResult,
  BashOptions,
  FileSystem,
  MoonBashFetchRequest,
  MoonBashFetchResponse,
  MoonBashVmRequest,
  MoonBashVmResponse,
} from "./types";

export type {
  ExecResult,
  BashOptions,
  FileSystem,
  MoonBashFetchRequest,
  MoonBashFetchResponse,
  NetworkOptions,
  MoonBashVmRequest,
  MoonBashVmResponse,
  TimerOptions,
  VmOptions,
} from "./types";

// Import the compiled MoonBit engine
// @ts-ignore - generated file has no type declarations
import { execute_with_state as mbExecuteWithState } from "../_build/js/debug/build/lib/entry/entry.js";

interface StateExecResult extends ExecResult {
  files?: Record<string, string>;
  dirs?: Record<string, string>;
  links?: Record<string, string>;
}

type MoonBashFetchBridge = (requestJson: string) => string;
type MoonBashSleepBridge = (durationMs: number) => string;
type MoonBashNowBridge = () => number;
type MoonBashVmBridge = (requestJson: string) => string;

declare global {
  // eslint-disable-next-line no-var
  var __moonbash_fetch: MoonBashFetchBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_sleep: MoonBashSleepBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_now: MoonBashNowBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_vm: MoonBashVmBridge | undefined;
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}

function isPromiseLike<T>(value: unknown): value is PromiseLike<T> {
  return typeof value === "object" &&
    value !== null &&
    "then" in value &&
    typeof (value as { then?: unknown }).then === "function";
}

function waitForPromise<T>(promise: Promise<T>): T {
  if (typeof SharedArrayBuffer === "undefined" || typeof Atomics === "undefined") {
    throw new Error(
      "moonbash: async bridge requires SharedArrayBuffer and Atomics support",
    );
  }

  const signal = new Int32Array(new SharedArrayBuffer(4));
  let resolved: T | undefined;
  let rejected: unknown;

  promise.then(
    (value) => {
      resolved = value;
      Atomics.store(signal, 0, 1);
      Atomics.notify(signal, 0, 1);
    },
    (error) => {
      rejected = error;
      Atomics.store(signal, 0, 2);
      Atomics.notify(signal, 0, 1);
    },
  );

  while (Atomics.load(signal, 0) === 0) {
    try {
      Atomics.wait(signal, 0, 0, 100);
    } catch (_error) {
      throw new Error("moonbash: Atomics.wait is not available in this runtime");
    }
  }

  if (Atomics.load(signal, 0) === 2) {
    throw rejected;
  }
  return resolved as T;
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

  private normalizeFetchResponse(
    response: MoonBashFetchResponse,
  ): MoonBashFetchResponse {
    return {
      ok: Boolean(response.ok),
      status: Number.isFinite(response.status) ? response.status : 0,
      statusText: response.statusText ?? "",
      headers: response.headers ?? {},
      body: response.body ?? "",
      error: response.error,
    };
  }

  private normalizeVmResponse(
    response: MoonBashVmResponse,
  ): MoonBashVmResponse {
    return {
      stdout: response.stdout ?? "",
      stderr: response.stderr ?? "",
      exitCode: Number.isFinite(response.exitCode) ? Math.floor(response.exitCode) : 1,
      error: response.error,
    };
  }

  private defaultNowMs(): number {
    if (typeof performance !== "undefined" && typeof performance.now === "function") {
      const value = performance.now();
      return Number.isFinite(value) ? Math.floor(value) : 0;
    }
    if (typeof Date !== "undefined" && typeof Date.now === "function") {
      const value = Date.now();
      if (!Number.isFinite(value)) {
        return 0;
      }
      return Math.floor(value % 2147483647);
    }
    return 0;
  }

  private defaultSleep(durationMs: number): void {
    if (!Number.isFinite(durationMs) || durationMs <= 0) {
      return;
    }
    const waitMs = Math.floor(durationMs);

    if (
      typeof SharedArrayBuffer !== "undefined" &&
      typeof Atomics !== "undefined" &&
      typeof setTimeout === "function"
    ) {
      waitForPromise(new Promise<void>((resolve) => {
        setTimeout(resolve, waitMs);
      }));
      return;
    }

    const start = this.defaultNowMs();
    while (this.defaultNowMs() - start < waitMs) {
      // Busy-wait fallback for runtimes without Atomics.wait support.
    }
  }

  private defaultFetch(
    request: MoonBashFetchRequest,
  ): Promise<MoonBashFetchResponse> {
    if (typeof fetch !== "function") {
      return Promise.resolve({
        ok: false,
        status: 0,
        statusText: "",
        headers: {},
        body: "",
        error: "global fetch is not available in this runtime",
      });
    }
    const init: RequestInit = {
      method: request.method || "GET",
      headers: request.headers,
      body: request.body,
    };
    return fetch(request.url, init).then(async (response) => {
      const headers: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        headers[key] = value;
      });
      return {
        ok: response.ok,
        status: response.status,
        statusText: response.statusText,
        headers,
        body: await response.text(),
      };
    });
  }

  private createFetchBridge(): MoonBashFetchBridge | undefined {
    const networkOptions = this.options.network;
    if (!networkOptions) {
      return undefined;
    }

    const fetchImpl = networkOptions.fetch
      ? networkOptions.fetch
      : (request: MoonBashFetchRequest) => this.defaultFetch(request);

    return (requestJson: string): string => {
      try {
        const request = JSON.parse(requestJson) as MoonBashFetchRequest;
        const maybeResponse = fetchImpl(request);
        const response = isPromiseLike<MoonBashFetchResponse>(maybeResponse)
          ? waitForPromise(Promise.resolve(maybeResponse))
          : maybeResponse;

        return JSON.stringify(this.normalizeFetchResponse(response));
      } catch (error) {
        return JSON.stringify({
          ok: false,
          status: 0,
          statusText: "",
          headers: {},
          body: "",
          error: toErrorMessage(error),
        } satisfies MoonBashFetchResponse);
      }
    };
  }

  private createSleepBridge(): MoonBashSleepBridge {
    const sleepImpl = this.options.timers?.sleep
      ? this.options.timers.sleep
      : (durationMs: number) => this.defaultSleep(durationMs);

    return (durationMs: number): string => {
      try {
        const waitMs = Number.isFinite(durationMs) ? Math.max(0, Math.floor(durationMs)) : 0;
        const maybeResult = sleepImpl(waitMs);
        if (isPromiseLike<void>(maybeResult)) {
          waitForPromise(Promise.resolve(maybeResult));
        }
        return "";
      } catch (error) {
        return toErrorMessage(error);
      }
    };
  }

  private createNowBridge(): MoonBashNowBridge {
    const nowImpl = this.options.timers?.now;
    if (!nowImpl) {
      return () => this.defaultNowMs();
    }
    return (): number => {
      try {
        const value = nowImpl();
        if (!Number.isFinite(value)) {
          return 0;
        }
        if (value < 0) {
          return 0;
        }
        return Math.floor(value) % 2147483647;
      } catch (_error) {
        return 0;
      }
    };
  }

  private createVmBridge(): MoonBashVmBridge | undefined {
    const vmImpl = this.options.vm?.run;
    if (!vmImpl) {
      return undefined;
    }

    return (requestJson: string): string => {
      try {
        const request = JSON.parse(requestJson) as MoonBashVmRequest;
        const maybeResponse = vmImpl(request);
        const response = isPromiseLike<MoonBashVmResponse>(maybeResponse)
          ? waitForPromise(Promise.resolve(maybeResponse))
          : maybeResponse;
        return JSON.stringify(this.normalizeVmResponse(response));
      } catch (error) {
        return JSON.stringify({
          stdout: "",
          stderr: "",
          exitCode: 1,
          error: toErrorMessage(error),
        } satisfies MoonBashVmResponse);
      }
    };
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
    const fetchBridge = this.createFetchBridge();
    const sleepBridge = this.createSleepBridge();
    const nowBridge = this.createNowBridge();
    const vmBridge = this.createVmBridge();
    const previousFetchBridge = globalThis.__moonbash_fetch;
    const previousSleepBridge = globalThis.__moonbash_sleep;
    const previousNowBridge = globalThis.__moonbash_now;
    const previousVmBridge = globalThis.__moonbash_vm;
    globalThis.__moonbash_fetch = fetchBridge;
    globalThis.__moonbash_sleep = sleepBridge;
    globalThis.__moonbash_now = nowBridge;
    globalThis.__moonbash_vm = vmBridge;

    try {
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
    } finally {
      if (previousFetchBridge === undefined) {
        delete globalThis.__moonbash_fetch;
      } else {
        globalThis.__moonbash_fetch = previousFetchBridge;
      }
      if (previousSleepBridge === undefined) {
        delete globalThis.__moonbash_sleep;
      } else {
        globalThis.__moonbash_sleep = previousSleepBridge;
      }
      if (previousNowBridge === undefined) {
        delete globalThis.__moonbash_now;
      } else {
        globalThis.__moonbash_now = previousNowBridge;
      }
      if (previousVmBridge === undefined) {
        delete globalThis.__moonbash_vm;
      } else {
        globalThis.__moonbash_vm = previousVmBridge;
      }
    }
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
