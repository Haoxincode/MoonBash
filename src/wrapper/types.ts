/**
 * MoonBash TypeScript Type Definitions
 * API-compatible with vercel-labs/just-bash
 */

export interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface MoonBashFetchRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
}

export interface MoonBashFetchResponse {
  ok: boolean;
  status: number;
  statusText?: string;
  headers?: Record<string, string>;
  body: string;
  error?: string;
}

export interface NetworkOptions {
  /**
   * Optional host fetch bridge.
   * Can be synchronous or Promise-based.
   */
  fetch?: (
    request: MoonBashFetchRequest
  ) => MoonBashFetchResponse | Promise<MoonBashFetchResponse>;
}

export type MoonBashVmRuntime = "python3" | "sqlite3";

export interface MoonBashVmRequest {
  runtime: MoonBashVmRuntime;
  args: string[];
  stdin?: string;
  cwd?: string;
  env?: Record<string, string>;
}

export interface MoonBashVmResponse {
  stdout: string;
  stderr: string;
  exitCode: number;
  error?: string;
}

export interface VmOptions {
  /**
   * Optional host VM bridge used by python3/sqlite3 commands.
   * Can be synchronous or Promise-based.
   */
  run?: (
    request: MoonBashVmRequest
  ) => MoonBashVmResponse | Promise<MoonBashVmResponse>;
}

export interface TimerOptions {
  /**
   * Optional sleep bridge used by sleep/timeout builtins.
   * Can be synchronous or Promise-based.
   */
  sleep?: (durationMs: number) => void | Promise<void>;

  /**
   * Optional monotonic clock (milliseconds).
   * Used by time/timeout builtins.
   */
  now?: () => number;
}

export interface BashOptions {
  /** Initial environment variables */
  env?: Record<string, string>;
  /** Initial working directory (default: "/home/user") */
  cwd?: string;
  /** Initial filesystem contents: path -> content mapping */
  files?: Record<string, string>;
  /** Execution limits */
  limits?: Partial<ExecutionLimits>;
  /** Enable debug tracing */
  trace?: boolean;
  /** Network bridge options used by curl/html-to-markdown */
  network?: NetworkOptions;
  /** Timer bridge options used by sleep/time/timeout */
  timers?: TimerOptions;
  /** VM bridge options used by python3/sqlite3 */
  vm?: VmOptions;
}

export interface ExecutionLimits {
  maxCallDepth: number;
  maxCommandCount: number;
  maxLoopIterations: number;
  maxStringLength: number;
  maxArrayElements: number;
  maxHeredocSize: number;
  maxSubstitutionDepth: number;
  maxGlobOperations: number;
}

export interface FileSystem {
  readFile(path: string): string;
  writeFile(path: string, content: string): void;
  appendFile(path: string, content: string): void;
  exists(path: string): boolean;
  stat(path: string): FileStat;
  readdir(path: string): DirentEntry[];
  mkdir(path: string, options?: { recursive?: boolean }): void;
  rm(path: string, options?: { recursive?: boolean; force?: boolean }): void;
  cp(src: string, dst: string, options?: { recursive?: boolean }): void;
  mv(src: string, dst: string): void;
}

export interface FileStat {
  isFile: boolean;
  isDirectory: boolean;
  isSymlink: boolean;
  size: number;
  mode: number;
  mtime: number;
}

export interface DirentEntry {
  name: string;
  type: "file" | "directory" | "symlink";
}
