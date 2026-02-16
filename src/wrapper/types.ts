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
  files?: Record<string, string>;
}

export interface MoonBashVmResponse {
  stdout: string;
  stderr: string;
  exitCode: number;
  error?: string;
  files?: Record<string, string>;
}

export interface VmWasmPythonOptions {
  /** Enable built-in Pyodide runtime for python3. */
  enabled?: boolean;
  /** Optional custom loader for Pyodide runtime. */
  loadRuntime?: () => unknown | Promise<unknown>;
  /** Optional Pyodide index URL passed to loadPyodide. */
  indexURL?: string;
}

export interface VmWasmSqliteOptions {
  /** Enable built-in sql.js runtime for sqlite3. */
  enabled?: boolean;
  /** Optional custom loader for sql.js runtime. */
  loadRuntime?: () => unknown | Promise<unknown>;
  /** Optional wasm file URL passed through locateFile. */
  wasmUrl?: string;
}

export interface VmWasmOptions {
  python?: VmWasmPythonOptions;
  sqlite?: VmWasmSqliteOptions;
}

export interface VmOptions {
  /**
   * Optional host VM bridge used by python3/sqlite3 commands.
   * Can be synchronous or Promise-based.
   */
  run?: (
    request: MoonBashVmRequest
  ) => MoonBashVmResponse | Promise<MoonBashVmResponse>;
  /** Optional built-in WASM runtime settings for python3/sqlite3. */
  wasm?: VmWasmOptions;
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

export interface InitialFileEntry {
  content?: string | Uint8Array;
  mode?: number;
}

export type InitialFileValue = string | Uint8Array | InitialFileEntry;
export type InitialFiles = Record<string, InitialFileValue>;

export interface BashOptions {
  /** Initial environment variables */
  env?: Record<string, string>;
  /** Initial working directory (default: "/home/user") */
  cwd?: string;
  /** Initial filesystem contents: path -> content mapping */
  files?: InitialFiles;
  /** Enable built-in Python runtime (defaults to WASM bridge). */
  python?: boolean;
  /** Enable built-in SQLite runtime (defaults to WASM bridge). */
  sqlite?: boolean;
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
