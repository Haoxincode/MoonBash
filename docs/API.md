# MoonBash API Specification

This document defines the public API surface of MoonBash, designed to be 100% compatible with `just-bash`.

## 1. Core Classes

### 1.1 `Bash`

The main entry point for creating and interacting with a Bash interpreter instance.

```typescript
class Bash {
  constructor(options?: BashOptions);

  /**
   * Execute a bash script and return the result.
   */
  exec(script: string, options?: ExecOptions): Promise<BashExecResult>;

  /**
   * Get the current filesystem instance.
   */
  getFs(): IFileSystem;

  /**
   * Get the current working directory.
   */
  getCwd(): string;

  /**
   * Get the current environment variables.
   */
  getEnv(): Record<string, string>;

  /**
   * Register a transform plugin for AST manipulation.
   */
  registerTransformPlugin(plugin: TransformPlugin): void;
}
```

### 1.2 `Sandbox`

Vercel Sandbox API-compatible wrapper around `Bash`.

```typescript
class Sandbox {
  constructor(options?: SandboxOptions);

  /**
   * Execute a command in the sandbox.
   */
  exec(command: string): Promise<ExecResult>;

  /**
   * Get the underlying Bash instance.
   */
  getBash(): Bash;
}
```

## 2. Configuration Types

### 2.1 `BashOptions`

```typescript
interface BashOptions {
  /**
   * Initial files to populate the virtual filesystem.
   * Keys are absolute paths, values are file contents.
   */
  files?: InitialFiles;

  /**
   * Initial environment variables.
   */
  env?: Record<string, string>;

  /**
   * Initial working directory. Default: "/home/user"
   */
  cwd?: string;

  /**
   * Filesystem implementation. Default: InMemoryFs
   */
  fs?: IFileSystem;

  /**
   * Execution safety limits.
   */
  executionLimits?: ExecutionLimits;

  /**
   * Network access configuration. Default: disabled
   */
  network?: NetworkConfig;

  /**
   * Restrict available commands to this list.
   * If not specified, all commands are available.
   */
  commands?: CommandName[];

  /**
   * Custom sleep implementation (for testing).
   */
  sleep?: (ms: number) => Promise<void>;

  /**
   * Register custom commands.
   */
  customCommands?: CustomCommand[];

  /**
   * Logging configuration.
   */
  logger?: BashLogger;

  /**
   * Performance tracing callback.
   */
  trace?: TraceCallback;

  /**
   * Defense-in-depth security configuration.
   */
  defenseInDepth?: DefenseInDepthConfig | boolean;
}
```

### 2.2 `ExecOptions`

```typescript
interface ExecOptions {
  /**
   * Additional environment variables for this execution only.
   */
  env?: Record<string, string>;

  /**
   * Override working directory for this execution only.
   */
  cwd?: string;

  /**
   * If true, skip script preprocessing.
   */
  rawScript?: boolean;

  /**
   * Provide stdin input for the script.
   */
  stdin?: string;
}
```

### 2.3 `ExecutionLimits`

```typescript
interface ExecutionLimits {
  /** Max function call/recursion depth. Default: 100 */
  maxCallDepth?: number;

  /** Max total commands executed. Default: 10000 */
  maxCommandCount?: number;

  /** Max iterations per loop. Default: 10000 */
  maxLoopIterations?: number;

  /** Max AWK loop iterations. Default: 10000 */
  maxAwkIterations?: number;

  /** Max SED loop iterations. Default: 10000 */
  maxSedIterations?: number;

  /** Max jq iterations. Default: 10000 */
  maxJqIterations?: number;

  /** Max glob filesystem operations. Default: 100000 */
  maxGlobOperations?: number;

  /** Max string length in bytes. Default: 10485760 (10MB) */
  maxStringLength?: number;

  /** Max array elements. Default: 100000 */
  maxArrayElements?: number;

  /** Max heredoc size. Default: 10485760 (10MB) */
  maxHeredocSize?: number;

  /** Max command substitution nesting depth. Default: 50 */
  maxSubstitutionDepth?: number;
}
```

### 2.4 `NetworkConfig`

```typescript
interface NetworkConfig {
  /**
   * URL prefixes that are allowed for network access.
   * Must include protocol and path prefix.
   * Example: ["https://api.github.com/repos/myorg/"]
   */
  allowedUrlPrefixes: string[];

  /**
   * Allowed HTTP methods. Default: ["GET", "HEAD"]
   */
  allowedMethods?: HttpMethod[];

  /**
   * Max redirects to follow. Default: 20
   */
  maxRedirects?: number;

  /**
   * Request timeout in milliseconds. Default: 30000
   */
  timeoutMs?: number;

  /**
   * Max response body size in bytes. Default: 10485760 (10MB)
   */
  maxResponseSize?: number;
}

type HttpMethod = "GET" | "HEAD" | "POST" | "PUT" | "DELETE" | "PATCH";
```

## 3. Result Types

### 3.1 `ExecResult`

```typescript
interface ExecResult {
  /** Standard output text. */
  stdout: string;

  /** Standard error text. */
  stderr: string;

  /** Process exit code. 0 = success. */
  exitCode: number;
}
```

### 3.2 `BashExecResult`

```typescript
interface BashExecResult extends ExecResult {
  /** Environment variables after execution. */
  env: Record<string, string>;

  /** Optional metadata from transform plugins. */
  metadata?: Record<string, unknown>;
}
```

## 4. Filesystem Interface

### 4.1 `IFileSystem`

All filesystem implementations must satisfy this interface.

```typescript
interface IFileSystem {
  readFile(path: string, options?: { encoding?: string }): Promise<string>;
  readFileBuffer(path: string): Promise<Uint8Array>;
  writeFile(path: string, content: string | Uint8Array,
            options?: { mode?: number }): Promise<void>;
  appendFile(path: string, content: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  stat(path: string): Promise<FsStat>;
  readdirWithFileTypes(path: string): Promise<DirentEntry[]>;
  mkdir(path: string, options?: { recursive?: boolean }): Promise<void>;
  rm(path: string, options?: { recursive?: boolean; force?: boolean }): Promise<void>;
  cp(src: string, dest: string,
     options?: { recursive?: boolean }): Promise<void>;
  symlink(target: string, path: string): Promise<void>;
  readlink(path: string): Promise<string>;
  chmod(path: string, mode: number): Promise<void>;
}
```

### 4.2 `FsStat`

```typescript
interface FsStat {
  isFile: boolean;
  isDirectory: boolean;
  isSymbolicLink: boolean;
  size: number;
  mode: number;
  mtime: Date;
}
```

### 4.3 `DirentEntry`

```typescript
interface DirentEntry {
  name: string;
  isFile(): boolean;
  isDirectory(): boolean;
  isSymbolicLink(): boolean;
}
```

## 5. Filesystem Implementations

### 5.1 `InMemoryFs`

```typescript
class InMemoryFs implements IFileSystem {
  constructor();

  // All IFileSystem methods implemented with pure in-memory storage.
  // Data stored in Map<string, FsEntry>.
  // No disk access whatsoever.
}
```

### 5.2 `OverlayFs`

```typescript
class OverlayFs implements IFileSystem {
  constructor(options: OverlayFsOptions);
}

interface OverlayFsOptions {
  /** Root directory on real filesystem to read from. */
  root: string;

  /** Virtual mount point. Default: "/home/user/project" */
  mountPoint?: string;

  /** If true, writes throw an error. Default: false */
  readOnly?: boolean;

  /** Max file size to read from disk. Default: 10MB */
  maxFileReadSize?: number;
}
```

### 5.3 `ReadWriteFs`

```typescript
class ReadWriteFs implements IFileSystem {
  constructor(rootDir: string);
  // Direct read/write to real filesystem via Node.js fs module.
}
```

### 5.4 `MountableFs`

```typescript
class MountableFs implements IFileSystem {
  constructor(baseFs: IFileSystem);

  /**
   * Mount a filesystem at a virtual path.
   * Cannot mount at root "/".
   */
  mount(mountPoint: string, fs: IFileSystem): void;

  /**
   * Unmount a filesystem.
   */
  unmount(mountPoint: string): void;
}
```

## 6. Command Extension

### 6.1 `CustomCommand`

```typescript
interface CustomCommand {
  name: string;
  execute(args: string[], ctx: CommandContext): Promise<ExecResult>;
}

// Lazy-loaded variant for code splitting
interface LazyCommand {
  name: string;
  load(): Promise<CustomCommand>;
}

/**
 * Helper to define a custom command.
 */
function defineCommand(
  name: string,
  fn: (args: string[], ctx: CommandContext) => Promise<ExecResult>
): CustomCommand;
```

### 6.2 `CommandContext`

Provided to all command implementations during execution.

```typescript
interface CommandContext {
  /** Virtual filesystem handle. */
  fs: IFileSystem;

  /** Current working directory. */
  cwd: string;

  /** Environment variables (Map to prevent prototype pollution). */
  env: Map<string, string>;

  /** Standard input for this command. */
  stdin: string;

  /** Execution limits. */
  limits: Required<ExecutionLimits>;

  /** Tracing callback. */
  trace?: TraceCallback;

  /** Execute a sub-command. */
  exec?: (command: string, options?: ExecOptions) => Promise<ExecResult>;

  /** Network fetch (only if network enabled). */
  fetch?: SecureFetch;

  /** Get all registered command names. */
  getRegisteredCommands?: () => string[];

  /** Custom sleep function. */
  sleep?: (ms: number) => Promise<void>;

  /** Open file descriptors. */
  fileDescriptors?: Map<number, string>;
}
```

## 7. Transform Plugins

### 7.1 `TransformPlugin`

```typescript
interface TransformPlugin {
  /** Unique plugin name. */
  name: string;

  /**
   * Transform the AST before execution.
   * Can modify, wrap, or analyze the AST.
   */
  transform(ctx: TransformContext): TransformResult;
}

interface TransformContext {
  /** The parsed AST. */
  ast: ScriptNode;

  /** The original script text. */
  source: string;
}

interface TransformResult {
  /** The (possibly modified) AST. */
  ast: ScriptNode;

  /** Optional metadata returned in BashExecResult. */
  metadata?: Record<string, unknown>;
}
```

## 8. Security Types

### 8.1 `DefenseInDepthConfig`

```typescript
interface DefenseInDepthConfig {
  /** Enable defense-in-depth protections. Default: true */
  enabled?: boolean;

  /** Log violations without blocking. Default: false */
  auditMode?: boolean;

  /** Callback when a violation is detected. */
  onViolation?: (violation: SecurityViolation) => void;

  /** Exclude specific violation types from checking. */
  excludeViolationTypes?: SecurityViolationType[];
}

interface SecurityViolation {
  type: SecurityViolationType;
  message: string;
  stack?: string;
}

type SecurityViolationType =
  | "function_constructor"
  | "eval"
  | "timers"
  | "async_constructors"
  | "weak_refs"
  | "reflect"
  | "proxy"
  | "process"
  | "require"
  | "webassembly"
  | "shared_memory";
```

## 9. Logging & Tracing

```typescript
interface BashLogger {
  info(message: string, data?: unknown): void;
  debug(message: string, data?: unknown): void;
}

type TraceCallback = (event: TraceEvent) => void;

interface TraceEvent {
  category: string;   // "command", "expansion", "pipeline", etc.
  name: string;        // Specific operation name
  durationMs: number;  // Execution duration
  metadata?: Record<string, unknown>;
}
```

## 10. Initial Files

```typescript
/**
 * Mapping of absolute file paths to file contents.
 * Used to pre-populate the virtual filesystem.
 */
type InitialFiles = Record<string, string | Uint8Array>;
```

## 11. Usage Examples

### Basic Usage

```typescript
import { Bash } from "moon-bash";

const bash = new Bash();
const result = await bash.exec("echo hello world");
// result.stdout === "hello world\n"
// result.exitCode === 0
```

### With Pre-populated Files

```typescript
const bash = new Bash({
  files: {
    "/data/input.csv": "name,age\nAlice,30\nBob,25\n",
    "/scripts/process.sh": "#!/bin/bash\ncat /data/input.csv | sort",
  },
});

const result = await bash.exec("bash /scripts/process.sh");
```

### With Custom Commands

```typescript
import { Bash, defineCommand } from "moon-bash";

const fetchData = defineCommand("fetch-data", async (args, ctx) => {
  return {
    stdout: JSON.stringify({ result: "ok" }),
    stderr: "",
    exitCode: 0,
  };
});

const bash = new Bash({ customCommands: [fetchData] });
const result = await bash.exec("fetch-data | jq .result");
```

### With Overlay Filesystem

```typescript
import { Bash, OverlayFs } from "moon-bash";

const fs = new OverlayFs({
  root: "/real/project/path",
  mountPoint: "/home/user/project",
});

const bash = new Bash({ fs });

// Reads from real filesystem, writes go to memory only
const result = await bash.exec("cat README.md | wc -l");
```

### With Network Access

```typescript
const bash = new Bash({
  network: {
    allowedUrlPrefixes: ["https://api.github.com/repos/myorg/"],
    allowedMethods: ["GET"],
    timeoutMs: 10000,
  },
});

const result = await bash.exec(
  'curl -s https://api.github.com/repos/myorg/myrepo | jq .stargazers_count'
);
```

### Restricted Command Set

```typescript
const bash = new Bash({
  commands: ["echo", "cat", "grep", "sort", "uniq", "wc"],
});

// Only listed commands are available
// Any other command will return "command not found"
```

### Transform Plugins

```typescript
import { Bash, TransformPlugin } from "moon-bash";

class AuditPlugin implements TransformPlugin {
  name = "audit";
  commands: string[] = [];

  transform(ctx) {
    // Walk AST and collect command names
    this.collectCommands(ctx.ast);
    return {
      ast: ctx.ast,
      metadata: { auditedCommands: this.commands },
    };
  }
}

const audit = new AuditPlugin();
const bash = new Bash();
bash.registerTransformPlugin(audit);

const result = await bash.exec("echo hello | grep hello");
console.log(result.metadata?.auditedCommands); // ["echo", "grep"]
```
