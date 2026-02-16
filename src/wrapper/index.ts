/**
 * MoonBash - Zero-dependency POSIX Shell Sandbox
 *
 * API-compatible with vercel-labs/just-bash.
 * Compiled from MoonBit to pure JavaScript (no WASM).
 */

import type {
  BashExecResult,
  BashLogger,
  ExecResult,
  ExecOptions,
  BashOptions,
  Command,
  CommandContext,
  CustomCommand,
  LazyCommand,
  ExecutionLimits,
  FileSystem,
  InitialFileEntry,
  InitialFileValue,
  InitialFiles,
  MoonBashFetchRequest,
  MoonBashFetchResponse,
  MoonBashVmRequest,
  MoonBashVmResponse,
} from "./types";

export type {
  BashExecResult,
  BashLogger,
  ExecResult,
  ExecOptions,
  BashOptions,
  Command,
  CommandContext,
  CustomCommand,
  LazyCommand,
  FileSystem,
  InitialFileEntry,
  InitialFileValue,
  InitialFiles,
  MoonBashFetchRequest,
  MoonBashFetchResponse,
  NetworkOptions,
  ExecutionLimits,
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
  modes?: Record<string, string>;
  env?: Record<string, string>;
}

type MoonBashFetchBridge = (requestJson: string) => string;
type MoonBashSleepBridge = (durationMs: number) => string;
type MoonBashNowBridge = () => number;
type MoonBashVmBridge = (requestJson: string) => string;
type MoonBashCustomBridge = (requestJson: string) => string;

interface MoonBashCustomRequest {
  name: string;
  args: string[];
  stdin?: string;
  cwd?: string;
  env?: Record<string, string>;
  files?: Record<string, string>;
}

interface MoonBashCustomResponse {
  handled: boolean;
  stdout: string;
  stderr: string;
  exitCode: number;
  error?: string;
  files?: Record<string, string>;
}

const DEFAULT_COMMAND_NAMES: string[] = [
  "echo",
  "cat",
  "pwd",
  "ls",
  "mkdir",
  "rm",
  "cp",
  "mv",
  "touch",
  "find",
  "head",
  "tail",
  "wc",
  "awk",
  "jq",
  "true",
  "false",
  "rmdir",
  "stat",
  "file",
  "tree",
  "du",
  "chmod",
  "ln",
  "readlink",
  "diff",
  "cmp",
  "comm",
  "base64",
  "expr",
  "yq",
  "xan",
  "csvlook",
  "md5sum",
  "sha1sum",
  "sha256sum",
  "gzip",
  "gunzip",
  "zcat",
  "python3",
  "sqlite3",
  "export",
  "unset",
  "set",
  "shift",
  "exit",
  "return",
  "break",
  "continue",
  "read",
  "mapfile",
  "readarray",
  "test",
  "[",
  "[[",
  "printf",
  "eval",
  "source",
  ".",
  "local",
  "declare",
  "typeset",
  "let",
  ":",
  "type",
  "command",
  "basename",
  "dirname",
  "seq",
  "rev",
  "nl",
  "fold",
  "expand",
  "unexpand",
  "paste",
  "column",
  "join",
  "tr",
  "sort",
  "uniq",
  "cut",
  "tee",
  "sed",
  "grep",
  "egrep",
  "fgrep",
  "rg",
  "xargs",
  "date",
  "env",
  "printenv",
  "which",
  "whoami",
  "hostname",
  "help",
  "clear",
  "history",
  "tac",
  "od",
  "alias",
  "unalias",
  "bash",
  "sh",
  "time",
  "sleep",
  "timeout",
];

interface PyodideFsLike {
  analyzePath(path: string): { exists: boolean };
  mkdir(path: string): void;
  readdir(path: string): string[];
  stat(path: string): { mode: number };
  isDir(mode: number): boolean;
  readFile(path: string, options?: { encoding: "utf8" }): string;
  writeFile(path: string, data: string): void;
  unlink(path: string): void;
}

interface PyodideRuntimeLike {
  FS: PyodideFsLike;
  globals: {
    set(name: string, value: unknown): void;
  };
  runPython(code: string): unknown;
}

interface SqlJsResultLike {
  values: unknown[][];
}

interface SqlJsDatabaseLike {
  exec(sql: string): SqlJsResultLike[];
  run(sql: string): void;
  export(): Uint8Array;
  close(): void;
}

interface SqlJsRuntimeLike {
  Database: new (data?: Uint8Array) => SqlJsDatabaseLike;
}

interface SqlJsInitOptions {
  locateFile?: (file: string) => string;
}

type SqlJsInitLike = (options?: SqlJsInitOptions) => Promise<SqlJsRuntimeLike>;
type VmBridgeImpl = (
  request: MoonBashVmRequest,
) => MoonBashVmResponse | Promise<MoonBashVmResponse>;

const PYODIDE_EXEC_SNIPPET = `
import contextlib
import io
import json
import os
import runpy
import sys
import traceback

_request = json.loads(__moonbash_request_json)
_args = _request.get("args") or []
_stdin = _request.get("stdin") or ""
_cwd = _request.get("cwd") or "/"
_env = _request.get("env") or {}

_stdout_io = io.StringIO()
_stderr_io = io.StringIO()
_exit_code = 0

_old_stdin = sys.stdin
_old_argv = list(sys.argv)
_old_cwd = os.getcwd()
_old_env = os.environ.copy()

try:
    sys.stdin = io.StringIO(_stdin)
    sys.argv = ["python3"] + list(_args)
    os.environ.clear()
    for _k, _v in _env.items():
        os.environ[str(_k)] = str(_v)

    if _cwd:
        os.makedirs(_cwd, exist_ok=True)
        os.chdir(_cwd)

    with contextlib.redirect_stdout(_stdout_io), contextlib.redirect_stderr(_stderr_io):
        if len(_args) == 0:
            _exit_code = 0
        elif _args[0] == "-c":
            _code = _args[1] if len(_args) > 1 else ""
            sys.argv = ["-c"] + _args[2:]
            exec(compile(_code, "<string>", "exec"), {"__name__": "__main__"})
        elif _args[0] == "-m":
            if len(_args) < 2:
                raise SystemExit(2)
            _mod = _args[1]
            sys.argv = [_mod] + _args[2:]
            runpy.run_module(_mod, run_name="__main__", alter_sys=True)
        else:
            _script = _args[0]
            sys.argv = [_script] + _args[1:]
            runpy.run_path(_script, run_name="__main__")
except SystemExit as _e:
    _code = _e.code
    if isinstance(_code, int):
        _exit_code = _code
    elif _code is None:
        _exit_code = 0
    else:
        _exit_code = 1
        _text = str(_code)
        if _text:
            _stderr_io.write(_text)
            if not _text.endswith("\\n"):
                _stderr_io.write("\\n")
except BaseException:
    _exit_code = 1
    _stderr_io.write(traceback.format_exc())
finally:
    sys.stdin = _old_stdin
    sys.argv = _old_argv
    os.chdir(_old_cwd)
    os.environ.clear()
    os.environ.update(_old_env)

json.dumps({
    "stdout": _stdout_io.getvalue(),
    "stderr": _stderr_io.getvalue(),
    "exitCode": int(_exit_code),
})
`.trim();

declare global {
  // eslint-disable-next-line no-var
  var __moonbash_fetch: MoonBashFetchBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_sleep: MoonBashSleepBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_now: MoonBashNowBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_vm: MoonBashVmBridge | undefined;
  // eslint-disable-next-line no-var
  var __moonbash_custom: MoonBashCustomBridge | undefined;
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

function shellSingleQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizePosixPath(inputPath: string, cwd = "/"): string {
  const base = inputPath.startsWith("/")
    ? inputPath
    : (cwd === "/" ? `/${inputPath}` : `${cwd}/${inputPath}`);
  const parts = base.split("/");
  const out: string[] = [];
  for (const part of parts) {
    if (!part || part === ".") {
      continue;
    }
    if (part === "..") {
      if (out.length > 0) {
        out.pop();
      }
      continue;
    }
    out.push(part);
  }
  return out.length === 0 ? "/" : `/${out.join("/")}`;
}

function listChildren(paths: string[], dirPath: string): string[] {
  const prefix = dirPath === "/" ? "/" : `${dirPath}/`;
  const names = new Set<string>();
  for (const path of paths) {
    if (!path.startsWith(prefix) || path === dirPath) {
      continue;
    }
    const rest = path.slice(prefix.length);
    if (!rest) {
      continue;
    }
    const slash = rest.indexOf("/");
    names.add(slash === -1 ? rest : rest.slice(0, slash));
  }
  return [...names].sort();
}

function splitSimplePipeline(script: string): string[] | null {
  const segments: string[] = [];
  let buf = "";
  let inSingle = false;
  let inDouble = false;
  let escaped = false;

  for (let i = 0; i < script.length; i += 1) {
    const ch = script[i];
    if (escaped) {
      buf += ch;
      escaped = false;
      continue;
    }
    if (ch === "\\" && !inSingle) {
      buf += ch;
      escaped = true;
      continue;
    }
    if (ch === "'" && !inDouble) {
      inSingle = !inSingle;
      buf += ch;
      continue;
    }
    if (ch === "\"" && !inSingle) {
      inDouble = !inDouble;
      buf += ch;
      continue;
    }
    if (!inSingle && !inDouble) {
      if (ch === ";" || ch === "&" || ch === ">" || ch === "<") {
        return null;
      }
      if (ch === "|" && script[i + 1] === "|") {
        return null;
      }
      if (ch === "|") {
        const segment = buf.trim();
        if (!segment) {
          return null;
        }
        segments.push(segment);
        buf = "";
        continue;
      }
    }
    buf += ch;
  }

  if (inSingle || inDouble || escaped) {
    return null;
  }
  const last = buf.trim();
  if (!last) {
    return null;
  }
  segments.push(last);
  return segments;
}

function parseSimpleArgs(commandText: string): string[] | null {
  const args: string[] = [];
  let buf = "";
  let inSingle = false;
  let inDouble = false;
  let escaped = false;

  for (let i = 0; i < commandText.length; i += 1) {
    const ch = commandText[i];
    if (escaped) {
      buf += ch;
      escaped = false;
      continue;
    }
    if (ch === "\\" && !inSingle) {
      escaped = true;
      continue;
    }
    if (ch === "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (ch === "\"" && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (!inSingle && !inDouble && /\s/.test(ch)) {
      if (buf.length > 0) {
        args.push(buf);
        buf = "";
      }
      continue;
    }
    buf += ch;
  }

  if (inSingle || inDouble || escaped) {
    return null;
  }
  if (buf.length > 0) {
    args.push(buf);
  }
  return args.length > 0 ? args : null;
}

export function getCommandNames(): string[] {
  return [...DEFAULT_COMMAND_NAMES];
}

export function isLazyCommand(command: CustomCommand): command is LazyCommand {
  return typeof (command as LazyCommand).load === "function";
}

export function defineCommand(
  name: string,
  fn: (args: string[], ctx: CommandContext) => Promise<ExecResult>,
): Command {
  return {
    name,
    execute: fn,
  };
}

export function createLazyCustomCommand(lazyCommand: LazyCommand): Command {
  let loaded: Command | null = null;
  return {
    name: lazyCommand.name,
    async execute(args: string[], ctx: CommandContext): Promise<ExecResult> {
      if (!loaded) {
        loaded = await lazyCommand.load();
      }
      return loaded.execute(args, ctx);
    },
  };
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
  private baseCwd: string;
  private baseEnv: Record<string, string>;
  private useDefaultLayout: boolean;
  private files: Record<string, string>;
  private dirs: Record<string, string>;
  private links: Record<string, string>;
  private modes: Record<string, string>;
  private eagerCustomCommands: Map<string, Command>;
  private lazyCustomCommands: Map<string, LazyCommand>;
  private pyodideRuntime: PyodideRuntimeLike | null;
  private pyodideRuntimePromise: Promise<PyodideRuntimeLike> | null;
  private sqlJsRuntime: SqlJsRuntimeLike | null;
  private sqlJsRuntimePromise: Promise<SqlJsRuntimeLike> | null;
  private pyodideTrackedFiles: Set<string>;
  readonly fs: FileSystem;

  constructor(options: BashOptions = {}) {
    const normalizedOptions: BashOptions = { ...options };
    const fsSnapshot = this.extractFsSnapshot((options as { fs?: unknown }).fs);
    if (fsSnapshot) {
      normalizedOptions.files = {
        ...(normalizedOptions.files ?? {}),
        ...fsSnapshot,
      };
    }
    if (typeof options.sleep === "function" && !options.timers?.sleep) {
      normalizedOptions.timers = { ...(options.timers ?? {}), sleep: options.sleep };
    }

    this.options = normalizedOptions;
    this.baseCwd = options.cwd && options.cwd.length > 0
      ? options.cwd
      : (options.files ? "/" : "/home/user");
    this.baseEnv = { ...(options.env ?? {}) };
    this.useDefaultLayout = options.files === undefined && !options.cwd;
    const initialFs = this.normalizeInitialFiles(options.files);
    this.files = initialFs.files;
    this.dirs = {};
    this.links = {};
    this.modes = initialFs.modes;
    this.eagerCustomCommands = new Map();
    this.lazyCustomCommands = new Map();
    this.pyodideRuntime = null;
    this.pyodideRuntimePromise = null;
    this.sqlJsRuntime = null;
    this.sqlJsRuntimePromise = null;
    this.pyodideTrackedFiles = new Set();

    for (const customCommand of options.customCommands ?? []) {
      if (isLazyCommand(customCommand)) {
        this.lazyCustomCommands.set(customCommand.name, customCommand);
      } else {
        this.eagerCustomCommands.set(customCommand.name, customCommand);
      }
    }

    if (this.useDefaultLayout) {
      this.installDefaultBinStubs();
    }

    for (const filePath of Object.keys(this.files)) {
      this.addParentDirs(filePath);
    }
    this.fs = this.createFsApi();
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

  private installDefaultBinStubs(): void {
    const executableMode = (0o755).toString();
    for (const commandName of DEFAULT_COMMAND_NAMES) {
      const stubPath = `/bin/${commandName}`;
      if (!Object.prototype.hasOwnProperty.call(this.files, stubPath)) {
        this.files[stubPath] = "";
      }
      if (!Object.prototype.hasOwnProperty.call(this.modes, stubPath)) {
        this.modes[stubPath] = executableMode;
      }
    }
  }

  private createFsApi(): FileSystem {
    return {
      readFile: (path: string): string => {
        const normalized = this.normalizePath(path);
        if (Object.prototype.hasOwnProperty.call(this.files, normalized)) {
          return this.files[normalized];
        }
        throw new Error(`No such file: ${normalized}`);
      },
      writeFile: (path: string, content: string): void => {
        const normalized = this.normalizePath(path);
        this.files[normalized] = content;
        this.modes[normalized] = this.modes[normalized] ?? (0o644).toString();
        this.addParentDirs(normalized);
      },
      appendFile: (path: string, content: string): void => {
        const normalized = this.normalizePath(path);
        const existing = this.files[normalized] ?? "";
        this.files[normalized] = existing + content;
        this.modes[normalized] = this.modes[normalized] ?? (0o644).toString();
        this.addParentDirs(normalized);
      },
      exists: (path: string): boolean => {
        const normalized = this.normalizePath(path);
        return Object.prototype.hasOwnProperty.call(this.files, normalized) ||
          Object.prototype.hasOwnProperty.call(this.dirs, normalized) ||
          Object.prototype.hasOwnProperty.call(this.links, normalized);
      },
      stat: (path: string) => {
        const normalized = this.normalizePath(path);
        if (Object.prototype.hasOwnProperty.call(this.files, normalized)) {
          return {
            isFile: true,
            isDirectory: false,
            isSymlink: false,
            size: this.files[normalized].length,
            mode: Number.parseInt(this.modes[normalized] ?? "420", 10),
            mtime: 0,
          };
        }
        if (Object.prototype.hasOwnProperty.call(this.dirs, normalized)) {
          return {
            isFile: false,
            isDirectory: true,
            isSymlink: false,
            size: 0,
            mode: Number.parseInt(this.modes[normalized] ?? "493", 10),
            mtime: 0,
          };
        }
        if (Object.prototype.hasOwnProperty.call(this.links, normalized)) {
          return {
            isFile: false,
            isDirectory: false,
            isSymlink: true,
            size: this.links[normalized].length,
            mode: Number.parseInt(this.modes[normalized] ?? "511", 10),
            mtime: 0,
          };
        }
        throw new Error(`No such file: ${normalized}`);
      },
      readdir: (path: string) => {
        const normalized = this.normalizePath(path);
        const prefix = normalized === "/" ? "/" : `${normalized}/`;
        const names = new Set<string>();
        const collect = (candidatePath: string): void => {
          if (!candidatePath.startsWith(prefix)) {
            return;
          }
          const rest = candidatePath.slice(prefix.length);
          if (rest.length === 0) {
            return;
          }
          const slash = rest.indexOf("/");
          const name = slash === -1 ? rest : rest.slice(0, slash);
          if (name.length > 0) {
            names.add(name);
          }
        };
        for (const key of Object.keys(this.files)) {
          collect(key);
        }
        for (const key of Object.keys(this.dirs)) {
          collect(key);
        }
        for (const key of Object.keys(this.links)) {
          collect(key);
        }
        return [...names].sort().map((name) => {
          const child = normalized === "/" ? `/${name}` : `${normalized}/${name}`;
          const type = Object.prototype.hasOwnProperty.call(this.dirs, child)
            ? "directory"
            : Object.prototype.hasOwnProperty.call(this.links, child)
            ? "symlink"
            : "file";
          return { name, type } as const;
        });
      },
      mkdir: (path: string, options?: { recursive?: boolean }): void => {
        const normalized = this.normalizePath(path);
        if (options?.recursive) {
          const parts = normalized.split("/").filter(Boolean);
          let current = "";
          for (const part of parts) {
            current += `/${part}`;
            this.dirs[current] = "1";
            this.modes[current] = this.modes[current] ?? (0o755).toString();
          }
          return;
        }
        this.dirs[normalized] = "1";
        this.modes[normalized] = this.modes[normalized] ?? (0o755).toString();
      },
      rm: (path: string, options?: { recursive?: boolean; force?: boolean }): void => {
        const normalized = this.normalizePath(path);
        const removeEntry = (targetPath: string): void => {
          delete this.files[targetPath];
          delete this.links[targetPath];
          delete this.dirs[targetPath];
          delete this.modes[targetPath];
        };
        if (options?.recursive) {
          for (const key of Object.keys(this.files)) {
            if (key === normalized || key.startsWith(`${normalized}/`)) {
              removeEntry(key);
            }
          }
          for (const key of Object.keys(this.links)) {
            if (key === normalized || key.startsWith(`${normalized}/`)) {
              removeEntry(key);
            }
          }
          for (const key of Object.keys(this.dirs)) {
            if (key === normalized || key.startsWith(`${normalized}/`)) {
              removeEntry(key);
            }
          }
          return;
        }
        if (
          !Object.prototype.hasOwnProperty.call(this.files, normalized) &&
          !Object.prototype.hasOwnProperty.call(this.links, normalized) &&
          !Object.prototype.hasOwnProperty.call(this.dirs, normalized) &&
          !options?.force
        ) {
          throw new Error(`No such file: ${normalized}`);
        }
        removeEntry(normalized);
      },
      cp: (src: string, dst: string): void => {
        const srcPath = this.normalizePath(src);
        const dstPath = this.normalizePath(dst);
        if (!Object.prototype.hasOwnProperty.call(this.files, srcPath)) {
          throw new Error(`No such file: ${srcPath}`);
        }
        this.files[dstPath] = this.files[srcPath];
        this.modes[dstPath] = this.modes[srcPath] ?? (0o644).toString();
        this.addParentDirs(dstPath);
      },
      mv: (src: string, dst: string): void => {
        const srcPath = this.normalizePath(src);
        const dstPath = this.normalizePath(dst);
        if (!Object.prototype.hasOwnProperty.call(this.files, srcPath)) {
          throw new Error(`No such file: ${srcPath}`);
        }
        this.files[dstPath] = this.files[srcPath];
        this.modes[dstPath] = this.modes[srcPath] ?? (0o644).toString();
        delete this.files[srcPath];
        delete this.modes[srcPath];
        this.addParentDirs(dstPath);
      },
      chmod: (path: string, mode: number): void => {
        const normalized = this.normalizePath(path);
        this.modes[normalized] = Math.floor(mode).toString();
      },
    };
  }

  private extractFsSnapshot(fsLike: unknown): InitialFiles | undefined {
    if (!fsLike || typeof fsLike !== "object") {
      return undefined;
    }
    const maybeSnapshot = fsLike as {
      __moonbash_snapshot?: () => unknown;
    };
    if (typeof maybeSnapshot.__moonbash_snapshot !== "function") {
      return undefined;
    }
    const raw = maybeSnapshot.__moonbash_snapshot();
    if (!raw || typeof raw !== "object") {
      return undefined;
    }

    const out: InitialFiles = {};
    for (const [path, value] of Object.entries(raw as Record<string, unknown>)) {
      if (typeof value === "string" || value instanceof Uint8Array) {
        out[path] = value;
      } else if (value === null || value === undefined) {
        out[path] = "";
      } else if (typeof value === "object") {
        out[path] = value as InitialFileEntry;
      } else {
        out[path] = String(value);
      }
    }
    return out;
  }

  private normalizeInitialFiles(files?: InitialFiles): {
    files: Record<string, string>;
    modes: Record<string, string>;
  } {
    const normalizedFiles: Record<string, string> = {};
    const normalizedModes: Record<string, string> = {};
    if (!files || typeof files !== "object") {
      return { files: normalizedFiles, modes: normalizedModes };
    }

    for (const [rawPath, rawValue] of Object.entries(files)) {
      const path = this.normalizePath(rawPath);
      const parsed = this.normalizeInitialFileValue(rawValue);
      normalizedFiles[path] = parsed.content;
      if (parsed.mode !== null) {
        normalizedModes[path] = parsed.mode.toString();
      }
    }

    return { files: normalizedFiles, modes: normalizedModes };
  }

  private normalizeInitialFileValue(value: InitialFileValue): {
    content: string;
    mode: number | null;
  } {
    if (typeof value === "string") {
      return { content: value, mode: null };
    }

    if (value instanceof Uint8Array) {
      return { content: this.decodeInitialFileBytes(value), mode: null };
    }

    if (value && typeof value === "object") {
      const entry = value as { content?: unknown; mode?: unknown };
      return {
        content: this.normalizeInitialFileContent(entry.content),
        mode: this.normalizeInitialFileMode(entry.mode),
      };
    }

    return { content: "", mode: null };
  }

  private normalizeInitialFileContent(content: unknown): string {
    if (typeof content === "string") {
      return content;
    }
    if (content instanceof Uint8Array) {
      return this.decodeInitialFileBytes(content);
    }
    if (content === null || content === undefined) {
      return "";
    }
    return String(content);
  }

  private decodeInitialFileBytes(bytes: Uint8Array): string {
    if (typeof TextDecoder !== "undefined") {
      return new TextDecoder().decode(bytes);
    }
    let out = "";
    for (const byte of bytes) {
      out += String.fromCharCode(byte);
    }
    return out;
  }

  private normalizeInitialFileMode(mode: unknown): number | null {
    if (typeof mode === "number") {
      if (!Number.isFinite(mode) || mode < 0) {
        return null;
      }
      return Math.floor(mode);
    }
    if (typeof mode !== "string") {
      return null;
    }
    const trimmed = mode.trim();
    if (trimmed.length === 0) {
      return null;
    }
    if (/^0[oO][0-7]+$/.test(trimmed)) {
      return parseInt(trimmed.slice(2), 8);
    }
    if (/^[0-7]{3,4}$/.test(trimmed)) {
      return parseInt(trimmed, 8);
    }
    const parsed = Number.parseInt(trimmed, 10);
    if (!Number.isFinite(parsed) || parsed < 0) {
      return null;
    }
    return Math.floor(parsed);
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
    if (result.modes && typeof result.modes === "object") {
      this.modes = result.modes;
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
      files: response.files && typeof response.files === "object" ? response.files : undefined,
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
          // Keep host event-loop responsive for mocked async clocks in tests.
          Promise.resolve(maybeResult).catch(() => {});
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

  private getLogger(): BashLogger | undefined {
    const logger = this.options.logger;
    if (!logger || typeof logger.info !== "function" || typeof logger.debug !== "function") {
      return undefined;
    }
    return logger;
  }

  private getExecutionLimits(): Partial<ExecutionLimits> {
    return {
      ...(this.options.limits ?? {}),
      ...(this.options.executionLimits ?? {}),
    };
  }

  private encodeLimitsJson(): string {
    const limits = this.getExecutionLimits();
    const out: Record<string, string> = {};
    const set = (key: string, value: unknown): void => {
      if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
        return;
      }
      out[key] = Math.floor(value).toString();
    };
    set("max_call_depth", limits.maxCallDepth);
    set("max_command_count", limits.maxCommandCount);
    set("max_loop_iterations", limits.maxLoopIterations);
    set("max_string_length", limits.maxStringLength);
    set("max_array_elements", limits.maxArrayElements);
    set("max_heredoc_size", limits.maxHeredocSize);
    set("max_substitution_depth", limits.maxSubstitutionDepth);
    set("max_glob_operations", limits.maxGlobOperations);
    set("max_awk_iterations", limits.maxAwkIterations);
    set("max_sed_iterations", limits.maxSedIterations);
    set("max_jq_iterations", limits.maxJqIterations);
    return JSON.stringify(out);
  }

  private hasCustomCommands(): boolean {
    return this.eagerCustomCommands.size > 0 || this.lazyCustomCommands.size > 0;
  }

  private async resolveCustomCommand(name: string): Promise<Command | undefined> {
    const eager = this.eagerCustomCommands.get(name);
    if (eager) {
      return eager;
    }
    const lazy = this.lazyCustomCommands.get(name);
    if (!lazy) {
      return undefined;
    }
    const loaded = await lazy.load();
    this.eagerCustomCommands.set(name, loaded);
    this.lazyCustomCommands.delete(name);
    return loaded;
  }

  private buildCustomPrelude(script: string): string {
    if (!this.hasCustomCommands()) {
      return script;
    }
    const names = new Set<string>();
    for (const name of this.eagerCustomCommands.keys()) {
      names.add(name);
    }
    for (const name of this.lazyCustomCommands.keys()) {
      names.add(name);
    }
    const lines: string[] = [];
    for (const name of names) {
      // Custom command names are sourced from trusted host code.
      lines.push(`${name}() { __moonbash_custom__ ${shellSingleQuote(name)} "$@"; }`);
    }
    if (lines.length === 0) {
      return script;
    }
    return `${lines.join("\n")}\n${script}`;
  }

  private listCustomCommandNames(): string[] {
    const names: string[] = [];
    for (const name of this.eagerCustomCommands.keys()) {
      names.push(name);
    }
    for (const name of this.lazyCustomCommands.keys()) {
      names.push(name);
    }
    return names;
  }

  private scriptReferencesCustomCommand(script: string): boolean {
    const names = this.listCustomCommandNames();
    for (const name of names) {
      const pattern = new RegExp(`(^|[\\s|])${escapeRegExp(name)}($|[\\s|])`);
      if (pattern.test(script)) {
        return true;
      }
    }
    return false;
  }

  private async tryExecuteWithCustomCommands(
    script: string,
    effectiveEnv: Record<string, string>,
    cwd: string,
    execOptions: ExecOptions,
  ): Promise<BashExecResult | null> {
    if (!this.hasCustomCommands() || !this.scriptReferencesCustomCommand(script)) {
      return null;
    }

    const segments = splitSimplePipeline(script);
    if (!segments) {
      return null;
    }

    let pipelineInput = execOptions.stdin ?? "";
    let finalStdout = "";
    let finalExitCode = 0;
    const stderrParts: string[] = [];

    for (const segment of segments) {
      const parsedArgs = parseSimpleArgs(segment);
      if (!parsedArgs || parsedArgs.length === 0) {
        return null;
      }
      const commandName = parsedArgs[0];
      const commandArgs = parsedArgs.slice(1);
      const customCommand = await this.resolveCustomCommand(commandName);

      if (customCommand) {
        const commandEnv = new Map<string, string>(Object.entries(effectiveEnv));
        const result = await customCommand.execute(commandArgs, {
          fs: this.fs,
          cwd,
          env: commandEnv,
          stdin: pipelineInput,
          exec: (command: string, options: ExecOptions = {}) =>
            this.exec(command, {
              ...options,
              cwd: options.cwd ?? cwd,
              env: { ...effectiveEnv, ...(options.env ?? {}) },
            }),
        });
        const stdout = result.stdout ?? "";
        const stderr = result.stderr ?? "";
        finalStdout = stdout;
        finalExitCode = Number.isFinite(result.exitCode) ? result.exitCode : 1;
        pipelineInput = stdout;
        if (stderr.length > 0) {
          stderrParts.push(stderr);
        }
        continue;
      }

      const result = await this.exec(segment, {
        cwd,
        env: { ...effectiveEnv },
        stdin: pipelineInput,
      });
      finalStdout = result.stdout ?? "";
      finalExitCode = result.exitCode;
      pipelineInput = finalStdout;
      if (result.stderr.length > 0) {
        stderrParts.push(result.stderr);
      }
    }

    return {
      stdout: finalStdout,
      stderr: stderrParts.join(""),
      exitCode: finalExitCode,
      env: { ...effectiveEnv },
    };
  }

  private createCustomBridge(
    limitsJson: string,
    layoutMode: "default" | "minimal",
  ): MoonBashCustomBridge | undefined {
    if (!this.hasCustomCommands()) {
      return undefined;
    }

    return (requestJson: string): string => {
      try {
        const request = JSON.parse(requestJson) as MoonBashCustomRequest;
        const maybeResponse = this.runCustomCommandBridge(request, limitsJson, layoutMode);
        const response = isPromiseLike<MoonBashCustomResponse>(maybeResponse)
          ? waitForPromise(Promise.resolve(maybeResponse))
          : maybeResponse;
        return JSON.stringify(this.normalizeCustomResponse(response));
      } catch (error) {
        return JSON.stringify({
          handled: false,
          stdout: "",
          stderr: "",
          exitCode: 1,
          error: toErrorMessage(error),
        } satisfies MoonBashCustomResponse);
      }
    };
  }

  private normalizeCustomResponse(response: MoonBashCustomResponse): MoonBashCustomResponse {
    return {
      handled: Boolean(response.handled),
      stdout: response.stdout ?? "",
      stderr: response.stderr ?? "",
      exitCode: Number.isFinite(response.exitCode) ? Math.floor(response.exitCode) : 1,
      error: response.error,
      files: response.files && typeof response.files === "object" ? response.files : undefined,
    };
  }

  private async runCustomCommandBridge(
    request: MoonBashCustomRequest,
    limitsJson: string,
    layoutMode: "default" | "minimal",
  ): Promise<MoonBashCustomResponse> {
    if (!request || typeof request.name !== "string") {
      return { handled: false, stdout: "", stderr: "", exitCode: 1 };
    }

    const customCommand = await this.resolveCustomCommand(request.name);
    if (!customCommand) {
      return { handled: false, stdout: "", stderr: "", exitCode: 127 };
    }

    const cwd = normalizePosixPath(request.cwd ?? "/");
    const envObject: Record<string, string> = { ...(request.env ?? {}) };
    let filesState: Record<string, string> = { ...(request.files ?? {}) };

    const fsApi: FileSystem = {
      readFile: (path: string): string => {
        const normalized = normalizePosixPath(path, cwd);
        if (!Object.prototype.hasOwnProperty.call(filesState, normalized)) {
          throw new Error(`No such file: ${normalized}`);
        }
        return filesState[normalized];
      },
      writeFile: (path: string, content: string): void => {
        const normalized = normalizePosixPath(path, cwd);
        filesState[normalized] = content;
      },
      appendFile: (path: string, content: string): void => {
        const normalized = normalizePosixPath(path, cwd);
        filesState[normalized] = (filesState[normalized] ?? "") + content;
      },
      exists: (path: string): boolean => {
        const normalized = normalizePosixPath(path, cwd);
        if (Object.prototype.hasOwnProperty.call(filesState, normalized)) {
          return true;
        }
        const allPaths = Object.keys(filesState);
        return allPaths.some((candidate) => candidate.startsWith(`${normalized}/`));
      },
      stat: (path: string) => {
        const normalized = normalizePosixPath(path, cwd);
        if (Object.prototype.hasOwnProperty.call(filesState, normalized)) {
          return {
            isFile: true,
            isDirectory: false,
            isSymlink: false,
            size: filesState[normalized].length,
            mode: 0o644,
            mtime: 0,
          };
        }
        const allPaths = Object.keys(filesState);
        if (allPaths.some((candidate) => candidate.startsWith(`${normalized}/`))) {
          return {
            isFile: false,
            isDirectory: true,
            isSymlink: false,
            size: 0,
            mode: 0o755,
            mtime: 0,
          };
        }
        throw new Error(`No such file: ${normalized}`);
      },
      readdir: (path: string) => {
        const normalized = normalizePosixPath(path, cwd);
        const children = listChildren(Object.keys(filesState), normalized);
        return children.map((name) => ({ name, type: "file" as const }));
      },
      mkdir: (_path: string): void => {
        // Directories are inferred from file paths in this lightweight bridge.
      },
      rm: (path: string, options?: { recursive?: boolean }): void => {
        const normalized = normalizePosixPath(path, cwd);
        if (options?.recursive) {
          for (const filePath of Object.keys(filesState)) {
            if (filePath === normalized || filePath.startsWith(`${normalized}/`)) {
              delete filesState[filePath];
            }
          }
          return;
        }
        delete filesState[normalized];
      },
      cp: (src: string, dst: string): void => {
        const srcPath = normalizePosixPath(src, cwd);
        const dstPath = normalizePosixPath(dst, cwd);
        if (!Object.prototype.hasOwnProperty.call(filesState, srcPath)) {
          throw new Error(`No such file: ${srcPath}`);
        }
        filesState[dstPath] = filesState[srcPath];
      },
      mv: (src: string, dst: string): void => {
        const srcPath = normalizePosixPath(src, cwd);
        const dstPath = normalizePosixPath(dst, cwd);
        if (!Object.prototype.hasOwnProperty.call(filesState, srcPath)) {
          throw new Error(`No such file: ${srcPath}`);
        }
        filesState[dstPath] = filesState[srcPath];
        delete filesState[srcPath];
      },
      chmod: (_path: string, _mode: number): void => {
        // No-op in lightweight custom bridge FS.
      },
    };

    const execFn = async (
      command: string,
      options: ExecOptions = {},
    ): Promise<ExecResult> => {
      const subEnv = {
        ...envObject,
        ...(options.env ?? {}),
      };
      const subCwd = normalizePosixPath(options.cwd ?? cwd);
      const subResult = JSON.parse(mbExecuteWithState(
        command,
        JSON.stringify(subEnv),
        JSON.stringify(filesState),
        "{}",
        "{}",
        "{}",
        subCwd,
        limitsJson,
        layoutMode,
      )) as StateExecResult;
      filesState = { ...(subResult.files ?? filesState) };
      return {
        stdout: subResult.stdout ?? "",
        stderr: subResult.stderr ?? "",
        exitCode: Number.isFinite(subResult.exitCode) ? subResult.exitCode : 1,
      };
    };

    const context: CommandContext = {
      fs: fsApi,
      cwd,
      env: new Map(Object.entries(envObject)),
      stdin: request.stdin ?? "",
      exec: execFn,
    };

    try {
      const maybeResult = customCommand.execute(
        Array.isArray(request.args) ? request.args : [],
        context,
      );
      const result = isPromiseLike<ExecResult>(maybeResult)
        ? await Promise.resolve(maybeResult)
        : maybeResult;
      return {
        handled: true,
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? "",
        exitCode: Number.isFinite(result.exitCode) ? Math.floor(result.exitCode) : 1,
        files: filesState,
      };
    } catch (error) {
      return {
        handled: true,
        stdout: "",
        stderr: "",
        exitCode: 1,
        error: toErrorMessage(error),
        files: filesState,
      };
    }
  }

  private invokeDynamicImport(specifier: string): Promise<unknown> {
    return import(/* @vite-ignore */ specifier);
  }

  private isNodeRuntime(): boolean {
    const maybeProcess = globalThis as {
      process?: {
        versions?: {
          node?: string;
        };
      };
    };
    return typeof maybeProcess.process?.versions?.node === "string";
  }

  private async resolveNodeModulePath(specifier: string): Promise<string | undefined> {
    if (!this.isNodeRuntime()) {
      return undefined;
    }
    try {
      const nodeModule = await this.invokeDynamicImport("node:module") as {
        createRequire?: unknown;
        default?: {
          createRequire?: unknown;
        };
      };
      const createRequire = nodeModule.createRequire ?? nodeModule.default?.createRequire;
      if (typeof createRequire !== "function") {
        return undefined;
      }
      const requireFn = createRequire(import.meta.url) as {
        resolve?: (moduleName: string) => string;
      };
      if (typeof requireFn.resolve !== "function") {
        return undefined;
      }
      return requireFn.resolve(specifier);
    } catch (_error) {
      return undefined;
    }
  }

  private async resolveNodeDirname(pathValue: string): Promise<string | undefined> {
    if (!this.isNodeRuntime()) {
      return undefined;
    }
    try {
      const nodePath = await this.invokeDynamicImport("node:path") as {
        dirname?: unknown;
        default?: {
          dirname?: unknown;
        };
      };
      const dirname = nodePath.dirname ?? nodePath.default?.dirname;
      if (typeof dirname !== "function") {
        return undefined;
      }
      return dirname(pathValue);
    } catch (_error) {
      return undefined;
    }
  }

  private ensureTrailingSlash(pathValue: string): string {
    if (pathValue.endsWith("/") || pathValue.endsWith("\\")) {
      return pathValue;
    }
    return `${pathValue}/`;
  }

  private shouldEnablePythonWasm(): boolean {
    return this.options.python === true || this.options.vm?.wasm?.python?.enabled === true;
  }

  private shouldEnableSqliteWasm(): boolean {
    return this.options.sqlite === true || this.options.vm?.wasm?.sqlite?.enabled === true;
  }

  private normalizeVmPath(inputPath: string): string {
    if (!inputPath || inputPath.length === 0) {
      return "/";
    }
    const normalizedSlashes = inputPath.replace(/\\/g, "/");
    const absolute = normalizedSlashes.startsWith("/") ? normalizedSlashes : `/${normalizedSlashes}`;
    const out: string[] = [];
    for (const part of absolute.split("/")) {
      if (!part || part === ".") {
        continue;
      }
      if (part === "..") {
        if (out.length > 0) {
          out.pop();
        }
        continue;
      }
      out.push(part);
    }
    if (out.length === 0) {
      return "/";
    }
    return `/${out.join("/")}`;
  }

  private normalizeVmCwd(cwd?: string): string {
    if (!cwd || cwd.length === 0) {
      return "/";
    }
    return this.normalizeVmPath(cwd);
  }

  private normalizeVmFiles(files?: Record<string, string>): Record<string, string> {
    const normalized: Record<string, string> = {};
    if (!files || typeof files !== "object") {
      return normalized;
    }
    for (const [rawPath, rawContent] of Object.entries(files)) {
      const path = this.normalizeVmPath(rawPath);
      if (path === "/") {
        continue;
      }
      normalized[path] = rawContent ?? "";
    }
    return normalized;
  }

  private getVmTopRoot(path: string): string {
    const normalized = this.normalizeVmPath(path);
    const parts = normalized.split("/").filter(Boolean);
    if (parts.length === 0) {
      return "/";
    }
    return `/${parts[0]}`;
  }

  private ensurePyodideDir(runtime: PyodideRuntimeLike, dirPath: string): void {
    const normalized = this.normalizeVmPath(dirPath);
    if (normalized === "/") {
      return;
    }
    const parts = normalized.split("/").filter(Boolean);
    let current = "";
    for (const part of parts) {
      current += `/${part}`;
      try {
        if (!runtime.FS.analyzePath(current).exists) {
          runtime.FS.mkdir(current);
        }
      } catch (_error) {
        // Ignore race/invalid path errors; write step will surface real failure.
      }
    }
  }

  private writePyodideFile(runtime: PyodideRuntimeLike, path: string, content: string): void {
    const normalized = this.normalizeVmPath(path);
    if (normalized === "/") {
      return;
    }
    const slash = normalized.lastIndexOf("/");
    const parentDir = slash <= 0 ? "/" : normalized.slice(0, slash);
    this.ensurePyodideDir(runtime, parentDir);
    runtime.FS.writeFile(normalized, content ?? "");
  }

  private deletePyodideFile(runtime: PyodideRuntimeLike, path: string): void {
    const normalized = this.normalizeVmPath(path);
    if (normalized === "/") {
      return;
    }
    try {
      if (runtime.FS.analyzePath(normalized).exists) {
        runtime.FS.unlink(normalized);
      }
    } catch (_error) {
      // Ignore missing/unlink failures for non-tracked files.
    }
  }

  private readPyodideFile(runtime: PyodideRuntimeLike, path: string): string | undefined {
    const normalized = this.normalizeVmPath(path);
    if (normalized === "/") {
      return undefined;
    }
    try {
      if (!runtime.FS.analyzePath(normalized).exists) {
        return undefined;
      }
      return runtime.FS.readFile(normalized, { encoding: "utf8" });
    } catch (_error) {
      return undefined;
    }
  }

  private syncPyodideFiles(
    runtime: PyodideRuntimeLike,
    files: Record<string, string>,
  ): void {
    const nextPaths = new Set(Object.keys(files).map((path) => this.normalizeVmPath(path)));
    for (const trackedPath of this.pyodideTrackedFiles) {
      if (!nextPaths.has(trackedPath)) {
        this.deletePyodideFile(runtime, trackedPath);
      }
    }
    for (const [path, content] of Object.entries(files)) {
      this.writePyodideFile(runtime, path, content);
    }
    this.pyodideTrackedFiles = nextPaths;
  }

  private collectPyodideFilesFromRoots(
    runtime: PyodideRuntimeLike,
    roots: Set<string>,
    outFiles: Record<string, string>,
  ): void {
    const visitedDirs = new Set<string>();
    const maxDepth = 24;
    const maxFiles = 20000;
    let fileCount = 0;

    const walk = (dir: string, depth: number): void => {
      if (depth > maxDepth || fileCount >= maxFiles) {
        return;
      }
      const normalizedDir = this.normalizeVmPath(dir);
      if (visitedDirs.has(normalizedDir)) {
        return;
      }
      visitedDirs.add(normalizedDir);

      let entries: string[];
      try {
        entries = runtime.FS.readdir(normalizedDir);
      } catch (_error) {
        return;
      }

      for (const name of entries) {
        if (name === "." || name === "..") {
          continue;
        }
        const child = normalizedDir === "/" ? `/${name}` : `${normalizedDir}/${name}`;
        let stat: { mode: number };
        try {
          stat = runtime.FS.stat(child);
        } catch (_error) {
          continue;
        }

        if (runtime.FS.isDir(stat.mode)) {
          walk(child, depth + 1);
          continue;
        }

        const content = this.readPyodideFile(runtime, child);
        if (content !== undefined) {
          outFiles[this.normalizeVmPath(child)] = content;
        }
        fileCount += 1;
        if (fileCount >= maxFiles) {
          return;
        }
      }
    };

    for (const root of roots) {
      walk(root, 0);
    }
  }

  private resolvePyodideFilesSnapshot(
    runtime: PyodideRuntimeLike,
    request: MoonBashVmRequest,
    baseFiles: Record<string, string>,
  ): Record<string, string> {
    const snapshot: Record<string, string> = {};
    for (const path of this.pyodideTrackedFiles) {
      const content = this.readPyodideFile(runtime, path);
      if (content !== undefined) {
        snapshot[path] = content;
      }
    }

    const roots = new Set<string>();
    for (const path of Object.keys(baseFiles)) {
      const root = this.getVmTopRoot(path);
      if (root !== "/") {
        roots.add(root);
      }
    }

    if (request.cwd && request.cwd.startsWith("/")) {
      const cwdRoot = this.getVmTopRoot(request.cwd);
      if (cwdRoot !== "/") {
        roots.add(cwdRoot);
      }
    }

    if (Array.isArray(request.args) && request.args.length > 0) {
      const scriptPath = request.args[0];
      if (typeof scriptPath === "string" && scriptPath.startsWith("/")) {
        const scriptRoot = this.getVmTopRoot(scriptPath);
        if (scriptRoot !== "/") {
          roots.add(scriptRoot);
        }
      }
    }

    if (roots.size > 0) {
      this.collectPyodideFilesFromRoots(runtime, roots, snapshot);
    }

    this.pyodideTrackedFiles = new Set(Object.keys(snapshot));
    return snapshot;
  }

  private async loadDefaultPyodideRuntime(): Promise<PyodideRuntimeLike> {
    const pythonOptions = this.options.vm?.wasm?.python;
    let loadPyodideFn: ((options?: { indexURL?: string }) => Promise<unknown>) | null = null;
    const globalLoader = (globalThis as { loadPyodide?: unknown }).loadPyodide;
    if (typeof globalLoader === "function") {
      loadPyodideFn = globalLoader as (options?: { indexURL?: string }) => Promise<unknown>;
    }

    if (!loadPyodideFn) {
      let mod: unknown;
      try {
        mod = await this.invokeDynamicImport("pyodide");
      } catch (error) {
        throw new Error(
          `moonbash: python3 wasm runtime requires Pyodide (module \"pyodide\"). ${toErrorMessage(error)}`,
        );
      }
      const maybeModule = mod as {
        loadPyodide?: unknown;
        default?: unknown;
      };
      const maybeFn = maybeModule.loadPyodide ??
        (
          maybeModule.default as {
            loadPyodide?: unknown;
          } | undefined
        )?.loadPyodide ??
        maybeModule.default;
      if (typeof maybeFn !== "function") {
        throw new Error("moonbash: unable to locate loadPyodide() in module \"pyodide\"");
      }
      loadPyodideFn = maybeFn as (options?: { indexURL?: string }) => Promise<unknown>;
    }

    let indexURL = pythonOptions?.indexURL;
    if (!indexURL) {
      const pyodideAsmPath = await this.resolveNodeModulePath("pyodide/pyodide.asm.js");
      if (pyodideAsmPath) {
        const pyodideDir = await this.resolveNodeDirname(pyodideAsmPath);
        if (pyodideDir) {
          indexURL = this.ensureTrailingSlash(pyodideDir);
        }
      }
    }

    const runtime = await loadPyodideFn(indexURL ? { indexURL } : undefined);
    if (!runtime || typeof runtime !== "object") {
      throw new Error("moonbash: invalid Pyodide runtime object");
    }
    const candidate = runtime as {
      FS?: unknown;
      globals?: unknown;
      runPython?: unknown;
    };
    if (
      !candidate.FS ||
      !candidate.globals ||
      typeof candidate.runPython !== "function"
    ) {
      throw new Error("moonbash: Pyodide runtime is missing required APIs");
    }
    return runtime as PyodideRuntimeLike;
  }

  private getPyodideRuntime(): Promise<PyodideRuntimeLike> {
    if (this.pyodideRuntime) {
      return Promise.resolve(this.pyodideRuntime);
    }
    if (this.pyodideRuntimePromise) {
      return this.pyodideRuntimePromise;
    }
    const customLoader = this.options.vm?.wasm?.python?.loadRuntime;
    this.pyodideRuntimePromise = (async () => {
      let runtime: PyodideRuntimeLike;
      if (customLoader) {
        const loaded = await Promise.resolve(customLoader());
        if (!loaded || typeof loaded !== "object") {
          throw new Error("moonbash: vm.wasm.python.loadRuntime() returned invalid runtime");
        }
        const candidate = loaded as {
          FS?: unknown;
          globals?: unknown;
          runPython?: unknown;
        };
        if (
          !candidate.FS ||
          !candidate.globals ||
          typeof candidate.runPython !== "function"
        ) {
          throw new Error("moonbash: custom python runtime is missing required APIs");
        }
        runtime = loaded as PyodideRuntimeLike;
      } else {
        runtime = await this.loadDefaultPyodideRuntime();
      }
      this.pyodideRuntime = runtime;
      return runtime;
    })();
    return this.pyodideRuntimePromise;
  }

  private parsePyodideExecResult(raw: unknown): MoonBashVmResponse {
    let parsed: unknown = raw;
    if (typeof raw === "string") {
      parsed = JSON.parse(raw);
    } else if (raw && typeof raw === "object" && "toString" in raw) {
      const asString = String(raw);
      if (asString.startsWith("{") && asString.endsWith("}")) {
        parsed = JSON.parse(asString);
      }
    }
    if (!parsed || typeof parsed !== "object") {
      throw new Error("moonbash: python3 runtime returned invalid payload");
    }
    const obj = parsed as {
      stdout?: unknown;
      stderr?: unknown;
      exitCode?: unknown;
      error?: unknown;
    };
    return {
      stdout: typeof obj.stdout === "string" ? obj.stdout : "",
      stderr: typeof obj.stderr === "string" ? obj.stderr : "",
      exitCode: typeof obj.exitCode === "number" && Number.isFinite(obj.exitCode)
        ? Math.floor(obj.exitCode)
        : 1,
      error: typeof obj.error === "string" ? obj.error : undefined,
    };
  }

  private runPythonWithPyodide(request: MoonBashVmRequest): MoonBashVmResponse {
    if (!this.pyodideRuntime) {
      throw new Error("moonbash: python3 runtime is not initialized");
    }
    const runtime = this.pyodideRuntime;
    const vmFiles = this.normalizeVmFiles(request.files);
    this.syncPyodideFiles(runtime, vmFiles);
    const payload = {
      args: Array.isArray(request.args) ? request.args : [],
      stdin: request.stdin ?? "",
      cwd: this.normalizeVmCwd(request.cwd),
      env: request.env ?? {},
    };
    runtime.globals.set("__moonbash_request_json", JSON.stringify(payload));
    const rawResult = runtime.runPython(PYODIDE_EXEC_SNIPPET);
    const response = this.parsePyodideExecResult(rawResult);
    response.files = this.resolvePyodideFilesSnapshot(
      runtime,
      { ...request, cwd: payload.cwd, files: vmFiles },
      vmFiles,
    );
    return response;
  }

  private bytesToBinaryString(bytes: Uint8Array): string {
    let out = "";
    const chunk = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunk) {
      const part = bytes.subarray(offset, Math.min(offset + chunk, bytes.length));
      out += String.fromCharCode(...part);
    }
    return out;
  }

  private binaryStringToBytes(content: string): Uint8Array {
    const bytes = new Uint8Array(content.length);
    for (let i = 0; i < content.length; i += 1) {
      bytes[i] = content.charCodeAt(i) & 0xff;
    }
    return bytes;
  }

  private async loadDefaultSqlJsRuntime(): Promise<SqlJsRuntimeLike> {
    const sqliteOptions = this.options.vm?.wasm?.sqlite;
    let initSqlJs: SqlJsInitLike | null = null;
    const globalInit = (globalThis as { initSqlJs?: unknown }).initSqlJs;
    if (typeof globalInit === "function") {
      initSqlJs = globalInit as SqlJsInitLike;
    }

    if (!initSqlJs) {
      let mod: unknown;
      try {
        mod = await this.invokeDynamicImport("sql.js");
      } catch (error) {
        throw new Error(
          `moonbash: sqlite3 wasm runtime requires sql.js (module \"sql.js\"). ${toErrorMessage(error)}`,
        );
      }
      const maybeModule = mod as {
        default?: unknown;
        initSqlJs?: unknown;
      };
      const maybeFn = maybeModule.default ?? maybeModule.initSqlJs;
      if (typeof maybeFn !== "function") {
        throw new Error("moonbash: unable to locate sql.js initializer");
      }
      initSqlJs = maybeFn as SqlJsInitLike;
    }

    let resolvedWasmUrl = sqliteOptions?.wasmUrl;
    if (!resolvedWasmUrl) {
      resolvedWasmUrl = await this.resolveNodeModulePath("sql.js/dist/sql-wasm.wasm");
    }
    const locateFile = resolvedWasmUrl
      ? (_file: string) => resolvedWasmUrl as string
      : undefined;
    const runtime = await initSqlJs(locateFile ? { locateFile } : undefined);
    if (!runtime || typeof runtime !== "object" || typeof runtime.Database !== "function") {
      throw new Error("moonbash: invalid sql.js runtime object");
    }
    return runtime as SqlJsRuntimeLike;
  }

  private getSqlJsRuntime(): Promise<SqlJsRuntimeLike> {
    if (this.sqlJsRuntime) {
      return Promise.resolve(this.sqlJsRuntime);
    }
    if (this.sqlJsRuntimePromise) {
      return this.sqlJsRuntimePromise;
    }
    const customLoader = this.options.vm?.wasm?.sqlite?.loadRuntime;
    this.sqlJsRuntimePromise = (async () => {
      let runtime: SqlJsRuntimeLike;
      if (!customLoader) {
        runtime = await this.loadDefaultSqlJsRuntime();
      } else {
        const loaded = await Promise.resolve(customLoader());
        if (!loaded) {
          throw new Error("moonbash: vm.wasm.sqlite.loadRuntime() returned empty value");
        }
        if (typeof loaded === "function") {
          const initSqlJs = loaded as SqlJsInitLike;
          const sqliteOptions = this.options.vm?.wasm?.sqlite;
          const locateFile = sqliteOptions?.wasmUrl
            ? (_file: string) => sqliteOptions.wasmUrl as string
            : undefined;
          const initialized = await initSqlJs(locateFile ? { locateFile } : undefined);
          if (!initialized || typeof initialized.Database !== "function") {
            throw new Error("moonbash: custom sqlite init function returned invalid runtime");
          }
          runtime = initialized;
        } else {
          if (
            typeof loaded !== "object" ||
            typeof (loaded as { Database?: unknown }).Database !== "function"
          ) {
            throw new Error("moonbash: custom sqlite runtime is missing Database constructor");
          }
          runtime = loaded as SqlJsRuntimeLike;
        }
      }
      this.sqlJsRuntime = runtime;
      return runtime;
    })();
    return this.sqlJsRuntimePromise;
  }

  private parseSqliteArgs(args: string[]): {
    databasePath: string | null;
    sqlFromArgs: string;
  } {
    let databasePath: string | null = null;
    const sqlParts: string[] = [];
    for (let i = 0; i < args.length; i += 1) {
      const arg = args[i];
      if (arg === "-cmd" && i + 1 < args.length) {
        sqlParts.push(args[i + 1]);
        i += 1;
        continue;
      }
      if (arg.startsWith("-")) {
        continue;
      }
      if (databasePath === null) {
        databasePath = arg === ":memory:" ? ":memory:" : this.normalizeVmPath(arg);
        continue;
      }
      sqlParts.push(arg);
    }
    return {
      databasePath,
      sqlFromArgs: sqlParts.join("\n"),
    };
  }

  private formatSqliteCell(value: unknown): string {
    if (value === null || value === undefined) {
      return "";
    }
    if (value instanceof Uint8Array) {
      return this.bytesToBinaryString(value);
    }
    return String(value);
  }

  private runSqliteWithSqlJs(request: MoonBashVmRequest): MoonBashVmResponse {
    if (!this.sqlJsRuntime) {
      throw new Error("moonbash: sqlite3 runtime is not initialized");
    }
    const runtime = this.sqlJsRuntime;
    const files = this.normalizeVmFiles(request.files);
    const args = Array.isArray(request.args) ? request.args : [];
    const parsedArgs = this.parseSqliteArgs(args);
    const dbPath = parsedArgs.databasePath && parsedArgs.databasePath !== ":memory:"
      ? parsedArgs.databasePath
      : null;

    let db: SqlJsDatabaseLike;
    if (dbPath && Object.prototype.hasOwnProperty.call(files, dbPath)) {
      const fileContent = files[dbPath];
      try {
        db = new runtime.Database(this.binaryStringToBytes(fileContent));
      } catch (_error) {
        db = new runtime.Database();
        if (fileContent.trim().length > 0) {
          try {
            db.run(fileContent);
          } catch {
            // Ignore bootstrap SQL parsing errors; runtime SQL execution still returns an error.
          }
        }
      }
    } else {
      db = new runtime.Database();
    }

    const sqlText = [parsedArgs.sqlFromArgs, request.stdin ?? ""]
      .filter((part) => part.trim().length > 0)
      .join("\n");

    try {
      const lines: string[] = [];
      if (sqlText.trim().length > 0) {
        const resultSets = db.exec(sqlText);
        for (const resultSet of resultSets) {
          for (const row of resultSet.values) {
            lines.push(row.map((value) => this.formatSqliteCell(value)).join("|"));
          }
        }
      }

      const nextFiles: Record<string, string> = { ...files };
      if (dbPath) {
        nextFiles[dbPath] = this.bytesToBinaryString(db.export());
      }
      db.close();
      return {
        stdout: lines.length > 0 ? `${lines.join("\n")}\n` : "",
        stderr: "",
        exitCode: 0,
        files: nextFiles,
      };
    } catch (error) {
      try {
        db.close();
      } catch {
        // Ignore close failure after runtime error.
      }
      return {
        stdout: "",
        stderr: `${toErrorMessage(error)}\n`,
        exitCode: 1,
        files,
      };
    }
  }

  private createDefaultWasmVmImpl(): VmBridgeImpl | undefined {
    const enablePython = this.shouldEnablePythonWasm();
    const enableSqlite = this.shouldEnableSqliteWasm();
    if (!enablePython && !enableSqlite) {
      return undefined;
    }

    return (request: MoonBashVmRequest): MoonBashVmResponse => {
      if (request.runtime === "python3") {
        if (!enablePython) {
          return {
            stdout: "",
            stderr: "",
            exitCode: 1,
            error: "python3 runtime is disabled",
            files: this.normalizeVmFiles(request.files),
          };
        }
        return this.runPythonWithPyodide(request);
      }
      if (request.runtime === "sqlite3") {
        if (!enableSqlite) {
          return {
            stdout: "",
            stderr: "",
            exitCode: 1,
            error: "sqlite3 runtime is disabled",
            files: this.normalizeVmFiles(request.files),
          };
        }
        return this.runSqliteWithSqlJs(request);
      }
      return {
        stdout: "",
        stderr: "",
        exitCode: 1,
        error: `unsupported vm runtime: ${String(request.runtime)}`,
        files: this.normalizeVmFiles(request.files),
      };
    };
  }

  private async ensureDefaultVmRuntimesReady(): Promise<void> {
    if (this.options.vm?.run) {
      return;
    }
    if (this.shouldEnablePythonWasm()) {
      await this.getPyodideRuntime();
    }
    if (this.shouldEnableSqliteWasm()) {
      await this.getSqlJsRuntime();
    }
  }

  private createVmBridge(): MoonBashVmBridge | undefined {
    const vmImpl = this.options.vm?.run ?? this.createDefaultWasmVmImpl();
    if (!vmImpl) {
      return undefined;
    }

    return (requestJson: string): string => {
      try {
        const request = JSON.parse(requestJson) as MoonBashVmRequest;
        const maybeResponse = vmImpl(request);
        if (isPromiseLike<MoonBashVmResponse>(maybeResponse)) {
          return JSON.stringify({
            stdout: "",
            stderr: "",
            exitCode: 1,
            error: "async vm bridge is not supported by sync runtime",
          } satisfies MoonBashVmResponse);
        }
        const response = maybeResponse;
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
  async exec(script: string, execOptions: ExecOptions = {}): Promise<BashExecResult> {
    await this.ensureDefaultVmRuntimesReady();
    const logger = this.getLogger();
    const isEmptyScript = script.trim().length === 0;
    if (!isEmptyScript && logger) {
      logger.info("exec", { command: script });
    }

    const effectiveEnv: Record<string, string> = {
      ...this.baseEnv,
      ...(execOptions.env ?? {}),
    };
    if (Array.isArray(this.options.commands)) {
      const allowed = [...this.options.commands];
      if (this.hasCustomCommands()) {
        allowed.push("__moonbash_custom__");
      }
      effectiveEnv.__MOONBASH_ALLOWED_COMMANDS = allowed.join(",");
    }

    const cwd = normalizePosixPath(execOptions.cwd ?? this.baseCwd);
    const limitsJson = this.encodeLimitsJson();
    const layoutMode: "default" | "minimal" = this.useDefaultLayout ? "default" : "minimal";

    if (this.hasCustomCommands()) {
      const customResult = await this.tryExecuteWithCustomCommands(
        script,
        effectiveEnv,
        cwd,
        execOptions,
      );
      if (customResult) {
        if (!isEmptyScript && logger) {
          if (customResult.stdout.length > 0) {
            logger.debug("stdout", { output: customResult.stdout });
          }
          if (customResult.stderr.length > 0) {
            logger.info("stderr", { output: customResult.stderr });
          }
          logger.info("exit", { exitCode: customResult.exitCode });
        }
        return customResult;
      }
    }

    let scriptToRun = script;
    if (typeof execOptions.stdin === "string" && execOptions.stdin.length > 0) {
      scriptToRun = `printf '%s' ${shellSingleQuote(execOptions.stdin)} | ${scriptToRun}`;
    }
    const envJson = JSON.stringify(effectiveEnv);
    const filesJson = JSON.stringify(this.files);
    const dirsJson = JSON.stringify(this.dirs);
    const linksJson = JSON.stringify(this.links);
    const modesJson = JSON.stringify(this.modes);

    const fetchBridge = this.createFetchBridge();
    const sleepBridge = this.createSleepBridge();
    const nowBridge = this.createNowBridge();
    const vmBridge = this.createVmBridge();
    const customBridge = this.createCustomBridge(limitsJson, layoutMode);
    const previousFetchBridge = globalThis.__moonbash_fetch;
    const previousSleepBridge = globalThis.__moonbash_sleep;
    const previousNowBridge = globalThis.__moonbash_now;
    const previousVmBridge = globalThis.__moonbash_vm;
    const previousCustomBridge = globalThis.__moonbash_custom;
    globalThis.__moonbash_fetch = fetchBridge;
    globalThis.__moonbash_sleep = sleepBridge;
    globalThis.__moonbash_now = nowBridge;
    globalThis.__moonbash_vm = vmBridge;
    globalThis.__moonbash_custom = customBridge;

    try {
      const jsonResult = mbExecuteWithState(
        scriptToRun,
        envJson,
        filesJson,
        dirsJson,
        linksJson,
        modesJson,
        cwd,
        limitsJson,
        layoutMode,
      );
      const parsed = JSON.parse(jsonResult) as StateExecResult;
      this.applyState(parsed);
      const result: BashExecResult = {
        stdout: parsed.stdout ?? "",
        stderr: parsed.stderr ?? "",
        exitCode: Number.isFinite(parsed.exitCode) ? parsed.exitCode : 1,
        env: parsed.env && typeof parsed.env === "object" ? parsed.env : { ...effectiveEnv },
      };
      if (!isEmptyScript && logger) {
        if (result.stdout.length > 0) {
          logger.debug("stdout", { output: result.stdout });
        }
        if (result.stderr.length > 0) {
          logger.info("stderr", { output: result.stderr });
        }
        logger.info("exit", { exitCode: result.exitCode });
      }
      return result;
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
      if (previousCustomBridge === undefined) {
        delete globalThis.__moonbash_custom;
      } else {
        globalThis.__moonbash_custom = previousCustomBridge;
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
    this.modes[normalized] = (0o644).toString();
    this.addParentDirs(normalized);
  }

  getCwd(): string {
    return this.baseCwd;
  }

  getEnv(): Record<string, string> {
    return { ...this.baseEnv };
  }

  /**
   * Get the virtual filesystem interface.
   * Note: Currently not implemented - filesystem is internal to execution.
   */
  getFs(): FileSystem {
    return this.fs;
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
  options: BashOptions = {},
  execOptions: ExecOptions = {},
): Promise<BashExecResult> {
  const bash = new Bash(options);
  return bash.exec(script, execOptions);
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
  async exec(script: string, options: ExecOptions = {}): Promise<BashExecResult> {
    return this.bash.exec(script, options);
  }

  /**
   * Get the virtual filesystem for this sandbox.
   */
  getFs(): FileSystem {
    return this.bash.getFs();
  }
}
