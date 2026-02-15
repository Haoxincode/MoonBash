/**
 * MoonBash TypeScript Type Definitions
 * API-compatible with vercel-labs/just-bash
 */

export interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
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
