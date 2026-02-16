# MoonBash FFI & JavaScript Interop Design

## 1. Overview

MoonBash's core engine is written in MoonBit and compiled to pure JavaScript via `moon build --target js`. The FFI (Foreign Function Interface) layer handles all communication between the MoonBit core and the JavaScript host environment.

### Design Principles

1. **Minimal FFI Surface** - Only side-effectful operations cross the boundary
2. **Zero-Copy Strings** - MoonBit JS backend maps strings to native JS strings
3. **Async-First** - All I/O operations are async (Promise-based)
4. **Type-Safe Bridge** - Both sides have strong typing (MoonBit + TypeScript)

## 2. FFI Architecture

```
┌────────────────────────────────┐
│     TypeScript Host            │
│                                │
│  ┌──────────────────────────┐  │
│  │  FsBridge                │  │
│  │  NetworkBridge           │  │
│  │  TimeBridge              │  │
│  │  TraceBridge             │  │
│  └────────────┬─────────────┘  │
│               │ JS functions   │
├───────────────┼────────────────┤
│               │ extern "js"    │
│  ┌────────────▼─────────────┐  │
│  │  MoonBit FFI Layer       │  │
│  │  (ffi/*.mbt)             │  │
│  └──────────────────────────┘  │
│                                │
│     MoonBit Core Engine        │
└────────────────────────────────┘
```

## 3. Filesystem FFI

The filesystem is the most critical FFI boundary. InMemoryFs runs entirely in MoonBit, but OverlayFs and ReadWriteFs need host filesystem access.

### MoonBit Side (Callback Registration)

```moonbit
/// Filesystem callback functions provided by the host
struct FsCallbacks {
  read_file : (String) -> String     // path -> content
  write_file : (String, String) -> Unit  // path, content -> ()
  stat : (String) -> String          // path -> JSON-encoded FsStat
  readdir : (String) -> String       // path -> JSON-encoded entries
  exists : (String) -> Bool          // path -> bool
  mkdir : (String) -> Unit           // path -> ()
  rm : (String) -> Unit              // path -> ()
}

/// Register filesystem callbacks from host
pub fn set_fs_callbacks(callbacks : FsCallbacks) -> Unit {
  // Store callbacks for use by OverlayFs
}
```

### TypeScript Side (Callback Implementation)

```typescript
// bridge.ts
import * as fs from "node:fs/promises";
import { setFsCallbacks } from "./moon_bash-core.js";

export function setupFsBridge(rootDir: string) {
  setFsCallbacks({
    read_file: (path: string) => {
      const realPath = resolveToReal(rootDir, path);
      validatePathSecurity(rootDir, realPath);
      return fs.readFile(realPath, "utf-8");
    },

    write_file: (path: string, content: string) => {
      const realPath = resolveToReal(rootDir, path);
      validatePathSecurity(rootDir, realPath);
      return fs.writeFile(realPath, content, "utf-8");
    },

    stat: (path: string) => {
      const realPath = resolveToReal(rootDir, path);
      const stat = fs.stat(realPath);
      return JSON.stringify({
        isFile: stat.isFile(),
        isDirectory: stat.isDirectory(),
        isSymbolicLink: stat.isSymbolicLink(),
        size: stat.size,
        mode: stat.mode,
        mtime: stat.mtimeMs,
      });
    },

    readdir: (path: string) => {
      const realPath = resolveToReal(rootDir, path);
      const entries = fs.readdir(realPath, { withFileTypes: true });
      return JSON.stringify(entries.map(e => ({
        name: e.name,
        isFile: e.isFile(),
        isDirectory: e.isDirectory(),
        isSymbolicLink: e.isSymbolicLink(),
      })));
    },

    exists: (path: string) => {
      const realPath = resolveToReal(rootDir, path);
      try { fs.access(realPath); return true; }
      catch { return false; }
    },

    mkdir: (path: string) => {
      const realPath = resolveToReal(rootDir, path);
      return fs.mkdir(realPath, { recursive: true });
    },

    rm: (path: string) => {
      const realPath = resolveToReal(rootDir, path);
      return fs.rm(realPath, { recursive: true, force: true });
    },
  });
}
```

## 4. Async FFI Bridge

MoonBit's `@moonbitlang/async` library compiles to JavaScript Promises. This enables seamless async interop.

### MoonBit Async Functions

```moonbit
/// Execute a bash script (async entry point)
pub async fn execute(script : String, ctx : ExecContext) -> ExecResult {
  let ast = parse(script)!
  evaluate(ast, ctx)
}
```

When compiled to JS (`--target js`), this becomes:

```javascript
// Generated JS (simplified)
function execute(script, ctx) {
  return new Promise((resolve, reject) => {
    try {
      const ast = parse(script);
      resolve(evaluate(ast, ctx));
    } catch (e) {
      reject(e);
    }
  });
}
```

### Async FFI Calls (MoonBit calling JS async)

When MoonBit needs to call an async JS function (e.g., reading a file from disk):

```moonbit
// MoonBit side: declare external async function
extern "js" fn host_read_file_async(path : String) -> String =
  "async (path) => await globalThis.__moon_bash_fs.readFile(path)"
```

### JS Promise to MoonBit Async

```moonbit
// Using @moonbitlang/async/js_async for Promise interop
pub async fn read_overlay_file(path : String) -> String!FsError {
  try {
    host_read_file_async(path)
  } catch {
    e => raise FsError::IoError(e.to_string())
  }
}
```

## 5. Network FFI

Network access is routed through the host for security enforcement.

### MoonBit Side

```moonbit
struct NetworkCallbacks {
  fetch : (FetchRequest) -> String  // Returns JSON-encoded FetchResponse
}

struct FetchRequest {
  url : String
  method : String
  headers : Array[(String, String)]
  body : String?
}

extern "js" fn host_fetch(request_json : String) -> String =
  "async (req) => JSON.stringify(await globalThis.__moon_bash_network.fetch(JSON.parse(req)))"

pub async fn secure_fetch(request : FetchRequest) -> FetchResponse!NetworkError {
  let req_json = request.to_json().stringify()
  let resp_json = host_fetch(req_json)
  FetchResponse::from_json(resp_json)
}
```

### TypeScript Side

```typescript
export function setupNetworkBridge(config: NetworkConfig) {
  globalThis.__moon_bash_network = {
    fetch: async (req: FetchRequest): Promise<FetchResponse> => {
      // 1. Validate URL against allowedUrlPrefixes
      validateUrl(req.url, config.allowedUrlPrefixes);

      // 2. Validate HTTP method
      validateMethod(req.method, config.allowedMethods);

      // 3. Execute fetch with timeout
      const controller = new AbortController();
      const timeout = setTimeout(
        () => controller.abort(),
        config.timeoutMs
      );

      try {
        const response = await fetch(req.url, {
          method: req.method,
          headers: Object.fromEntries(req.headers),
          body: req.body,
          signal: controller.signal,
          redirect: "manual",
        });

        // 4. Validate response size
        const body = await readWithLimit(response, config.maxResponseSize);

        return {
          status: response.status,
          headers: Object.fromEntries(response.headers),
          body,
        };
      } finally {
        clearTimeout(timeout);
      }
    },
  };
}
```

## 6. Regex FFI (Fallback)

MoonBit's `@regexp` library handles most regex needs. For advanced features (backreferences, lookahead), we fall back to JS `RegExp` with timeout protection.

### MoonBit Side

```moonbit
/// Try MoonBit native regex first, fall back to JS if needed
pub fn regex_match(pattern : String, input : String) -> RegexResult!RegexError {
  // Try native @regexp first
  match @regexp.compile(pattern) {
    Ok(re) => {
      match re.find(input) {
        Some(m) => RegexResult::Match(m)
        None => RegexResult::NoMatch
      }
    }
    Err(_) => {
      // Pattern uses features not in @regexp (backrefs, lookahead)
      // Fall back to JS RegExp with timeout
      js_regex_fallback(pattern, input)
    }
  }
}

extern "js" fn js_regex_match(pattern : String, flags : String, input : String) -> String =
  #| (pattern, flags, input) => {
  #|   try {
  #|     const re = new RegExp(pattern, flags);
  #|     const match = re.exec(input);
  #|     return match ? JSON.stringify({matched: true, groups: [...match]}) :
  #|                     JSON.stringify({matched: false});
  #|   } catch (e) {
  #|     return JSON.stringify({error: e.message});
  #|   }
  #| }
```

## 7. Time & Sleep FFI

```moonbit
/// Get current timestamp (milliseconds)
extern "js" fn host_now() -> Int64 =
  "() => BigInt(Date.now())"

/// Sleep for specified milliseconds
extern "js" fn host_sleep(ms : Int) -> Unit =
  "async (ms) => new Promise(r => setTimeout(r, ms))"
```

## 8. Trace FFI

```moonbit
/// Emit a trace event to the host
extern "js" fn host_trace(event_json : String) -> Unit =
  "(json) => { if (globalThis.__moon_bash_trace) globalThis.__moon_bash_trace(JSON.parse(json)); }"

pub fn emit_trace(category : String, name : String, duration_ms : Double) -> Unit {
  let event = TraceEvent { category, name, duration_ms }
  host_trace(event.to_json().stringify())
}
```

## 9. Data Marshalling

### String Passing

MoonBit's JS backend maps `String` directly to JavaScript's native `string` type. **No encoding conversion or copying is needed.** This is a fundamental advantage over WASM-based solutions.

```
MoonBit String  ←→  JavaScript string
     ↕                    ↕
  Same V8 heap object (zero copy)
```

### Structured Data

For complex data crossing the FFI boundary, we use JSON serialization:

```moonbit
// MoonBit -> JS: serialize to JSON
let stat_json = fs_stat.to_json().stringify()
host_callback(stat_json)

// JS -> MoonBit: parse from JSON
let response = @json.parse(json_string)!
let status = response["status"].as_int()!
```

### Binary Data

For binary file content (`Bytes`):

```moonbit
extern "js" fn host_read_binary(path : String) -> Bytes =
  "async (path) => new Uint8Array(await globalThis.__moon_bash_fs.readBinary(path))"

extern "js" fn host_write_binary(path : String, data : Bytes) -> Unit =
  "async (path, data) => await globalThis.__moon_bash_fs.writeBinary(path, data)"
```

## 10. Global Registration Pattern

All FFI callbacks use a global namespace pattern for clean registration:

```typescript
// TypeScript host setup
declare global {
  var __moon_bash_fs: FsBridge;
  var __moon_bash_network: NetworkBridge;
  var __moon_bash_trace: TraceCallback | undefined;
  var __moon_bash_sleep: (ms: number) => Promise<void>;
}

export function initMoonBash(options: BashOptions) {
  // 1. Set up filesystem bridge
  globalThis.__moon_bash_fs = createFsBridge(options.fs);

  // 2. Set up network bridge (if enabled)
  if (options.network) {
    globalThis.__moon_bash_network = createNetworkBridge(options.network);
  }

  // 3. Set up tracing (if enabled)
  if (options.trace) {
    globalThis.__moon_bash_trace = options.trace;
  }

  // 4. Set up sleep
  globalThis.__moon_bash_sleep = options.sleep ?? defaultSleep;

  // 5. Initialize MoonBit core
  return createBashInstance(options);
}
```

## 11. Error Propagation

Errors flow across the FFI boundary via structured error types:

```
MoonBit Error (enum)
    │
    ├── Caught in MoonBit → return ExecResult with stderr + exitCode
    │
    └── Uncaught → propagates as JS Error
            │
            └── Caught in TypeScript wrapper
                    │
                    └── Re-thrown as typed BashError
```

```moonbit
// MoonBit error types
pub(open) enum BashError {
  ParseError(String)
  ExecError(String)
  LimitExceeded(String)
  FsError(FsError)
  NetworkError(String)
  InternalError(String)
}
```

```typescript
// TypeScript error wrapper
class BashError extends Error {
  constructor(
    public type: "parse" | "exec" | "limit" | "fs" | "network" | "internal",
    message: string,
  ) {
    super(message);
    this.name = "BashError";
  }
}
```
