# MoonBash Virtual Filesystem Design

## 1. Overview

MoonBash provides a complete virtual filesystem (VFS) abstraction that enables sandboxed file operations with no access to the host system. All filesystem implementations conform to a unified `IFileSystem` trait/interface.

Status note (as of 2026-02-19): the active Phase 4 filesystem direction is the TypeScript-layer AgentFS adapter (`docs/AGENTFS_ANALYSIS.md`). OverlayFs/MountableFs sections below are retained as legacy reference designs.

## 2. Filesystem Trait (MoonBit)

```moonbit
/// Core filesystem abstraction.
/// All operations are async to support both in-memory and external backends.
pub(open) trait IFileSystem {
  read_file(Self, String) -> String!FsError
  read_file_buffer(Self, String) -> Bytes!FsError
  write_file(Self, String, String) -> Unit!FsError
  write_file_bytes(Self, String, Bytes) -> Unit!FsError
  append_file(Self, String, String) -> Unit!FsError
  exists(Self, String) -> Bool
  stat(Self, String) -> FsStat!FsError
  readdir(Self, String) -> Array[DirentEntry]!FsError
  mkdir(Self, String, ~recursive : Bool = false) -> Unit!FsError
  rm(Self, String, ~recursive : Bool = false, ~force : Bool = false) -> Unit!FsError
  cp(Self, String, String, ~recursive : Bool = false) -> Unit!FsError
  symlink(Self, String, String) -> Unit!FsError
  readlink(Self, String) -> String!FsError
  chmod(Self, String, Int) -> Unit!FsError
}
```

## 3. Data Types

```moonbit
/// File system entry types
enum FsEntry {
  File(FileData)
  Directory(DirData)
  Symlink(SymlinkData)
}

struct FileData {
  content : @buffer.Buffer  // or Bytes for binary
  mode : Int                // Default: 0o644
  mtime : Int64             // Unix timestamp ms
}

struct DirData {
  mode : Int                // Default: 0o755
  mtime : Int64
}

struct SymlinkData {
  target : String
  mode : Int                // Default: 0o777
  mtime : Int64
}

/// File stat information
struct FsStat {
  is_file : Bool
  is_directory : Bool
  is_symlink : Bool
  size : Int
  mode : Int
  mtime : Int64
}

/// Directory entry
struct DirentEntry {
  name : String
  entry_type : EntryType
}

enum EntryType {
  File
  Directory
  Symlink
}

/// Filesystem errors
pub(open) enum FsError {
  NotFound(String)
  NotADirectory(String)
  NotAFile(String)
  IsADirectory(String)
  AlreadyExists(String)
  PermissionDenied(String)
  NotEmpty(String)
  InvalidPath(String)
  TooLarge(String)
  IoError(String)
}
```

## 4. InMemoryFs Implementation

The primary filesystem for sandboxed execution. All data lives in a `HashMap`.

### Data Structure

```moonbit
struct InMemoryFs {
  entries : @hashmap.HashMap[String, FsEntry]
}
```

### Path Handling

```
Input Path          Normalized Path
─────────────────   ─────────────────
/home/user/./docs   /home/user/docs
/home/user/../bin   /home/bin
/home/user/         /home/user
//home//user        /home/user
/home/user/\0evil   ERROR: null byte
```

**Rules:**
1. All paths are absolute (start with `/`)
2. `.` and `..` are resolved during normalization
3. Trailing slashes are stripped
4. Multiple consecutive slashes collapse to one
5. Null bytes (`\0`) in paths are rejected (security)
6. Symlinks are followed up to 40 levels deep (loop detection)

### Default Layout

When a new `InMemoryFs` is created, it contains:

```
/
├── home/
│   └── user/           # Default CWD
├── bin/                # Command stubs
├── usr/
│   └── bin/
└── tmp/
```

### Key Behaviors

| Operation | Behavior |
|---|---|
| `write_file` | Creates parent directories automatically |
| `read_file` | Follows symlinks, returns content as string |
| `mkdir -p` | Creates all intermediate directories |
| `rm -rf` | Removes directory and all descendants |
| `cp -r` | Deep copy of directory tree |
| `stat` | Returns metadata without following symlinks |
| `readdir` | Lists immediate children (not recursive) |

### Memory Management

- Files store content as MoonBit strings (UTF-8)
- Binary files stored as `Bytes`
- No memory-mapping or lazy loading
- Entire filesystem fits in JS heap
- GC handles cleanup when `InMemoryFs` is dropped

## 5. OverlayFs Implementation (Legacy Reference)

This section documents the original plan prior to the AgentFS architecture decision.

Copy-on-write filesystem that reads from a real directory but writes only to memory.

### Architecture

```
┌────────────────────────────────┐
│          OverlayFs             │
│                                │
│  ┌──────────┐  ┌────────────┐ │
│  │  Memory   │  │  Disk      │ │
│  │  Layer    │  │  Layer     │ │
│  │ (writes)  │  │ (reads)    │ │
│  └──────────┘  └────────────┘ │
│                                │
│  ┌──────────────────────────┐  │
│  │  Deleted Set             │  │
│  │  (tracks deletions)      │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

### Read Resolution

```
read_file("/home/user/project/foo.txt")
  │
  ├── Check deleted set → If deleted, return NotFound
  │
  ├── Check memory layer → If found, return memory version
  │
  └── Check disk layer → Read from real filesystem
      │
      ├── Map virtual path to real path
      │   /home/user/project/foo.txt → /real/path/foo.txt
      │
      ├── Validate path stays within root (security)
      │
      └── Read with size limit (default: 10MB)
```

### Write Handling

All writes go exclusively to the memory layer:

```
write_file("/home/user/project/foo.txt", "new content")
  │
  ├── Remove from deleted set (if previously deleted)
  │
  └── Store in memory layer
      (real disk is never modified)
```

### Configuration

```moonbit
struct OverlayFsConfig {
  root : String              // Real filesystem root
  mount_point : String       // Virtual path (default: /home/user/project)
  read_only : Bool           // Block all writes (default: false)
  max_file_read_size : Int   // Max read from disk (default: 10MB)
}
```

### Security

- Path traversal prevention: validates that resolved real paths stay within `root`
- Symlink target validation
- File size limits on disk reads
- No write to real disk ever

### FFI Requirement

OverlayFs requires FFI callbacks to read from the host filesystem:

```moonbit
// These functions are provided by the JS host environment
extern "js" fn host_read_file(path : String) -> String
extern "js" fn host_stat(path : String) -> String  // JSON-encoded FsStat
extern "js" fn host_readdir(path : String) -> String  // JSON-encoded entries
```

## 6. MountableFs Implementation (Legacy Reference)

This section documents the original multi-mount routing plan prior to AgentFS.

Virtual filesystem namespace that routes paths to different filesystem backends.

### Architecture

```
MountableFs
├── base_fs: InMemoryFs (handles everything not mounted)
├── mounts:
│   ├── /data     → ReadOnlyFs (knowledge base)
│   ├── /workspace → OverlayFs (project files)
│   └── /tmp      → InMemoryFs (scratch space)
```

### Path Resolution

```
resolve("/workspace/src/main.ts")
  │
  ├── Find longest matching mount point
  │   "/" → base_fs
  │   "/workspace" → overlay_fs  ← longest match
  │
  ├── Strip mount prefix
  │   "/workspace/src/main.ts" → "/src/main.ts"
  │
  └── Delegate to mounted filesystem
      overlay_fs.read_file("/src/main.ts")
```

### Rules

1. Cannot mount at root `/` (root is always the base filesystem)
2. Mount points must not overlap (e.g., can't mount at `/a` and `/a/b`)
3. Mount points are normalized (trailing slash stripped)
4. Mounting/unmounting is dynamic (can happen during execution)

## 7. Glob Pattern Matching

Used by pathname expansion and `find` command.

### Supported Patterns

| Pattern | Matches | Example |
|---|---|---|
| `*` | Any characters (except `/`) | `*.txt` matches `file.txt` |
| `?` | Any single character | `?.txt` matches `a.txt` |
| `[abc]` | Any character in set | `[abc].txt` matches `a.txt` |
| `[!abc]` | Any character not in set | `[!a].txt` matches `b.txt` |
| `[a-z]` | Character range | `[a-z].txt` matches `q.txt` |
| `**` | Recursive directory match | `**/*.txt` matches `a/b/c.txt` |

### Extended Glob (shopt -s extglob)

| Pattern | Meaning |
|---|---|
| `?(pattern)` | Zero or one occurrence |
| `*(pattern)` | Zero or more occurrences |
| `+(pattern)` | One or more occurrences |
| `@(pattern)` | Exactly one occurrence |
| `!(pattern)` | Anything except pattern |

### Shell Options Affecting Glob

| Option | Effect |
|---|---|
| `dotglob` | `*` matches files starting with `.` |
| `globstar` | `**` matches directories recursively |
| `nullglob` | Non-matching globs expand to nothing |
| `failglob` | Non-matching globs cause an error |
| `nocaseglob` | Case-insensitive matching |
| `noglob` (`set -f`) | Disable globbing entirely |

### Implementation

```moonbit
fn glob_match(pattern : String, path : String, opts : GlobOptions) -> Bool {
  // Convert glob pattern to internal representation
  // Match against path segments
  // Handle ** for recursive matching
  // Apply shell options (dotglob, nocaseglob, etc.)
}

fn expand_glob(
  pattern : String,
  cwd : String,
  fs : IFileSystem,
  opts : GlobOptions,
  limits : ExecutionLimits
) -> Array[String]!GlobError {
  // 1. Split pattern into directory components
  // 2. Walk filesystem from base directory
  // 3. Match each component against directory entries
  // 4. Collect matching paths
  // 5. Sort results
  // 6. Enforce maxGlobOperations limit
}
```

## 8. Performance Considerations

### InMemoryFs

- **HashMap lookup:** O(1) average for file access
- **Path normalization:** O(n) where n = path length
- **Recursive operations:** O(k) where k = number of entries in subtree
- **Memory:** Proportional to total file content size

### OverlayFs (Legacy)

- **Read (memory hit):** Same as InMemoryFs
- **Read (disk miss):** Depends on host I/O (async FFI call)
- **Write:** Same as InMemoryFs (memory only)
- **Deleted check:** O(1) HashSet lookup

### MountableFs (Legacy)

- **Mount resolution:** O(m) where m = number of mount points
- **After resolution:** Delegates to underlying filesystem

### Glob Expansion

- **Protected by `maxGlobOperations` limit** (default: 100,000)
- **Early termination** when limit exceeded
- Breadth-first traversal to avoid deep recursion
