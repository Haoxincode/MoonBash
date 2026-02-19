# MoonBash Development Roadmap

## Phase Overview

```
Phase 1: Foundation & MVP                    ✅ COMPLETE
  → Lexer, Parser, basic interpreter, InMemoryFs
  → 15 core commands
  → Build pipeline (MoonBit → JS → npm)

Phase 2: Shell Feature Completeness          ✅ COMPLETE
  → Full variable expansion, arrays, functions
  → Control flow (if/for/while/case)
  → Redirections and pipes
  → 20 additional commands

Phase 3: Text Processing Powerhouse          ✅ COMPLETE
  → grep, sed, awk (full implementations)
  → jq (via bobzhang/moonjq community package)
  → diff, comm, base64, md5sum, sha256sum, gzip, tar
  → All 87 target commands implemented

Phase 4: Production Hardening                🔧 IN PROGRESS
  → Comparison test suite: 523/523 (100%)
  → Security test suite: 27 files (fuzzing, prototype-pollution, sandbox)
  → Network: curl, html-to-markdown
  → Custom command bridge
  → Remaining: AgentFS adapter, npm publish
  → OverlayFs/MountableFs ⏸️ superseded by AgentFS

Phase 5: Multi-Platform Expansion            🔧 PARTIALLY COMPLETE
  → Data processors: yq, xan, csvlook (done)
  → Compression: gzip, gunzip, zcat, tar (done)
  → VM bridges: python3, sqlite3 (done)
  → Remaining: WASM target, browser bundle, REPL
```

**Current comparison test pass rate: 523/523 (100%)**
**Command coverage: 87/87 (100%)**

---

## Phase 1: Foundation & MVP ✅

**Goal:** Parse and execute simple bash scripts in-memory. Establish the full build pipeline from MoonBit source to npm package.

### 1.1 Project Setup

- [x] Initialize MoonBit project (`moon.mod.json`)
- [x] Configure JS backend (`moon.pkg.json` with `"targets": {"js": {...}}`)
- [x] Set up TypeScript wrapper project (`package.json`, `tsconfig.json`)
- [x] Configure build pipeline (`moon build --target js` → `tsup` bundle)
- [x] Set up test infrastructure (MoonBit tests + TS integration tests)
- [ ] CI/CD pipeline (GitHub Actions)

### 1.2 AST Types

- [x] Define all AST node types as MoonBit `enum`/`struct`
- [x] Implement `to_string()`/`Show` for debug printing
- [ ] Implement `to_json()` for AST serialization (debugging/transform plugins)

### 1.3 Lexer

- [x] Token type definition
- [x] Basic word tokenization
- [x] Quoted string handling (single, double, ANSI-C)
- [x] Escape sequence handling
- [x] Operator tokenization (`|`, `&&`, `||`, `;`, `&`)
- [x] Redirection tokenization (`<`, `>`, `>>`, `<<`, `<<<`, etc.)
- [x] Reserved word recognition (`if`, `then`, `else`, `fi`, `for`, `while`, etc.)
- [x] Comment stripping (`#`)
- [x] Heredoc content collection
- [x] Parser limit enforcement (MAX_INPUT_SIZE, MAX_TOKENS)
- [x] Comprehensive lexer tests

### 1.4 Parser

- [x] Recursive descent parser structure
- [x] Script (statement list) parsing
- [x] Simple command parsing (words + redirections)
- [x] Pipeline parsing (`cmd1 | cmd2`)
- [x] List parsing (`&&`, `||`, `;`, `&`)
- [x] Depth limit enforcement
- [x] Parser error reporting with position info
- [x] Parser tests

### 1.5 InMemoryFs

- [x] `HashMap`-based file storage
- [x] Path normalization (`.`, `..`, multiple slashes)
- [x] Null byte validation
- [x] `read_file`, `write_file`, `append_file`
- [x] `exists`, `stat`
- [x] `mkdir` (with recursive)
- [x] `rm` (with recursive + force)
- [x] `cp` (with recursive)
- [x] `readdir`
- [x] `symlink`, `readlink` (with loop detection)
- [x] `chmod`
- [x] Default layout creation (`/home/user`, `/bin`, `/tmp`)
- [x] Filesystem tests

### 1.6 Basic Interpreter

- [x] Execution context (env, cwd, stdin/stdout/stderr)
- [x] Simple command execution
- [x] Pipeline execution (stdout chaining)
- [x] Execution limit tracking (command count)
- [x] Exit code handling (`$?`)
- [x] Basic variable expansion (`$VAR`, `${VAR}`)
- [x] Command substitution (`$(cmd)`)
- [x] Word splitting on IFS

### 1.7 Phase 1 Commands

| Command | Priority | Status |
|---|---|---|
| `echo` | P0 | ✅ |
| `cat` | P0 | ✅ |
| `cd` | P0 | ✅ |
| `pwd` | P0 | ✅ |
| `ls` | P0 | ✅ |
| `mkdir` | P0 | ✅ |
| `rm` | P0 | ✅ |
| `cp` | P0 | ✅ |
| `mv` | P0 | ✅ |
| `touch` | P0 | ✅ |
| `head` | P0 | ✅ |
| `tail` | P0 | ✅ |
| `wc` | P0 | ✅ |
| `true` | P0 | ✅ |
| `false` | P0 | ✅ |

### 1.8 TypeScript Wrapper

- [x] `Bash` class with `exec()` method
- [x] `ExecResult` / `BashExecResult` types
- [x] `BashOptions` configuration
- [x] `InitialFiles` support
- [x] Bridge setup (global registration)
- [x] Type definitions (`.d.ts`)

### 1.9 Build & Publish

- [x] `moon build --target js` integration
- [x] `tsup` bundling (ESM + types)
- [x] npm package structure
- [x] Verify drop-in compatibility with just-bash API

### 1.10 Ecosystem-First Delivery Checklist

- [x] Create a command classification sheet (direct library / stdlib composition / state-machine / FFI).
- [x] For every Phase 1 command, record the primary MoonBit API(s) and fallback path.
- [x] Implement `cat`, `head`, `tail`, `wc` using shared line-stream helpers (`string` + `array`) rather than per-command parsing code.
- [x] Implement `ls`, `cd`, `pwd`, `mkdir`, `touch`, `rm`, `cp`, `mv` on top of a single VFS trait and common path-normalization utility.
- [x] Keep `echo`, `true`, `false` as builtin fast-path commands with zero allocator-heavy logic.
- [ ] Add tests that assert algorithm reuse behavior (for example: one shared sorter/path normalizer used by multiple commands).
- [ ] Add a merge gate: no new hand-rolled algorithm for a command if an approved package/stdlib path exists.

---

## Phase 2: Shell Feature Completeness ✅

**Goal:** Support the full range of Bash control flow, expansions, and shell builtins.

### 2.1 Compound Commands

- [x] `if / elif / else / fi`
- [x] `for var in words; do ... done`
- [x] C-style `for ((i=0; i<10; i++)); do ... done`
- [x] `while condition; do ... done`
- [x] `until condition; do ... done`
- [x] `case word in pattern) ... ;; esac`
- [x] Case terminators: `;;`, `;&`, `;;&`
- [x] Subshell `( commands )`
- [x] Group `{ commands; }`
- [x] Loop control: `break`, `continue` (with depth)

### 2.2 Variable System

- [x] Assignment (`VAR=value`)
- [x] Local variables (`local VAR=value`)
- [x] Export (`export VAR=value`)
- [x] Readonly (`readonly VAR=value`)
- [x] Unset (`unset VAR`)
- [x] Indexed arrays (`arr=(a b c)`, `${arr[0]}`, `${arr[@]}`)
- [ ] Associative arrays (`declare -A map`, `${map[key]}`)
- [x] Special variables (`$?`, `$#`, `$@`, `$*`, `$0`, `$$`, `$!`, `$RANDOM`, `$LINENO`)
- [x] `declare` with attributes (`-i`, `-l`, `-u`, `-n`, `-r`, `-a`, `-A`)
- [x] Namerefs (`declare -n ref=var`)

### 2.3 Full Expansion Engine

- [x] Brace expansion (`{a,b,c}`, `{1..10}`, `{1..10..2}`)
- [x] Tilde expansion (`~`, `~user`)
- [x] Full parameter expansion (all `${VAR...}` forms)
- [x] Arithmetic expansion (`$(( ))`)
- [ ] Process substitution (`<(cmd)`, `>(cmd)`)
- [x] Quote removal
- [x] Glob/pathname expansion (`*`, `?`, `[...]`)
- [ ] Extended globbing (`?(pat)`, `*(pat)`, `+(pat)`, `@(pat)`, `!(pat)`)
- [ ] Globstar (`**`)

### 2.4 Arithmetic

- [x] Integer arithmetic (`+`, `-`, `*`, `/`, `%`)
- [x] Comparison operators (`<`, `>`, `<=`, `>=`, `==`, `!=`)
- [x] Logical operators (`&&`, `||`, `!`)
- [x] Bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`)
- [x] Ternary (`cond ? a : b`)
- [x] Assignment operators (`=`, `+=`, `-=`, `*=`, `/=`, etc.)
- [x] Pre/post increment/decrement (`++`, `--`)
- [x] Parenthesized grouping
- [x] Int64 semantics (matching bash 64-bit wrap-around)

### 2.5 Conditionals

- [x] `test` / `[` command
- [x] `[[ ]]` extended test
- [x] File tests (`-f`, `-d`, `-e`, `-r`, `-w`, `-x`, `-s`, `-L`, etc.)
- [x] String tests (`-z`, `-n`, `=`, `!=`, `<`, `>`)
- [x] Numeric tests (`-eq`, `-ne`, `-lt`, `-le`, `-gt`, `-ge`)
- [x] Pattern matching in `[[ ]]` (`==`, `!=` with globs)
- [x] Regex matching (`=~`) with `BASH_REMATCH`
- [x] Logical operators (`-a`, `-o`, `!`, `&&`, `||`)
- [x] Variable test (`-v`)

### 2.6 Redirections

- [x] Input: `<`, `<<`, `<<<`, `<>`
- [x] Output: `>`, `>>`, `>|`
- [x] Stderr: `2>`, `2>>`, `&>`, `&>>`
- [x] Duplication: `>&`, `<&`
- [ ] FD variables: `{var}>file`
- [x] Multiple redirections per command
- [x] `/dev/null`, `/dev/stdin`, `/dev/stdout`, `/dev/stderr`

### 2.7 Functions

- [x] Function definition (`function name { }` and `name() { }`)
- [x] Function invocation
- [x] Positional parameters (`$1`, `$2`, ..., `$@`, `$*`, `$#`)
- [x] `shift`
- [x] Local variable scoping
- [x] `return` with exit code
- [x] Recursive call depth tracking

### 2.8 Shell Builtins

- [x] `set` (options + positional params, `set -o`/`+o`)
- [ ] `shopt` (shell options)
- [x] `alias` / `unalias`
- [x] `read` (with `-r`, `-p`, `-a`, `-d`, `-t`, `-n`)
- [x] `mapfile` / `readarray`
- [x] `printf` (full format string support)
- [x] `source` / `.`
- [ ] `pushd` / `popd` / `dirs`
- [ ] `trap` (limited - signal handling simulation)
- [x] `type` / `command`
- [ ] `hash`
- [ ] `enable`
- [x] `eval`
- [x] `exec` (redirection context + command dispatch)
- [x] `getopts`
- [x] `let`
- [x] `bash` / `sh` (sub-script execution)

### 2.9 Phase 2 Commands

| Command | Status | Notes |
|---|---|---|
| `env` | ✅ | Print environment |
| `export` | ✅ | Set env vars |
| `printenv` | ✅ | Print env vars |
| `basename` | ✅ | Path manipulation |
| `dirname` | ✅ | Path manipulation |
| `which` | ✅ | Command lookup |
| `seq` | ✅ | Number sequences |
| `date` | ✅ | Date formatting (FFI timer) |
| `sleep` | ✅ | Delay (via FFI timer bridge) |
| `expr` | ✅ | Expression evaluation (Pratt parser) |
| `tee` | ✅ | Stdin to file + stdout |
| `sort` | ✅ | Sort lines |
| `uniq` | ✅ | Deduplicate lines |
| `grep` | ✅ | Pattern matching (BRE/ERE/fixed) |
| `cut` | ✅ | Field extraction |
| `tr` | ✅ | Character translation |
| `rev` | ✅ | Reverse lines |
| `tac` | ✅ | Reverse file |
| `paste` | ✅ | Merge lines |
| `nl` | ✅ | Number lines |

### 2.10 Ecosystem-First Expansion Checklist

- [x] Implement `env`, `printenv`, `export`, `alias`, `unalias` on a unified session-state `HashMap` model.
- [x] Implement `basename`, `dirname` as pure path-string transforms shared by parser expansions and command layer.
- [x] Implement `sort`, `uniq`, `cut`, `tr`, `rev`, `paste`, `nl` with composable iterator/text helpers, not command-specific ad hoc loops.
- [x] Implement `seq` on top of the math/eval helper module with strict numeric bounds.
- [x] Implement `date` with adapter; keep output format compatibility tests in comparison suite.
- [x] Implement `sleep` via FFI timer bridge only; enforce cancellation + timeout behavior in security tests.
- [x] Before Phase 3, run a reuse audit documenting which commands still require custom engines (`awk` and parser-related paths).

---

## Phase 3: Text Processing Powerhouse ✅

**Goal:** Implement the complex text processing commands that make the sandbox useful for real data pipeline work.

### 3.1 grep (Full) ✅

- [x] BRE (Basic Regular Expressions)
- [x] ERE (Extended Regular Expressions) - `-E`
- [x] Fixed string matching - `-F`
- [x] All flags (`-i`, `-v`, `-c`, `-n`, `-l`, `-L`, `-w`, `-x`, `-q`)
- [x] Context lines (`-A`, `-B`, `-C`)
- [x] Recursive search (`-r`, `-R`)
- [x] Multiple patterns (`-e`)
- [ ] Pattern file (`-f`)
- [x] Integration with `@regexp` library
- [x] `egrep`, `fgrep`, `rg` aliases

### 3.2 sed (Full) ✅

- [x] Address types (line number, `$`, `/regex/`, range, step, negation `!`)
- [x] Substitute command (`s/pattern/replacement/flags`) with `g`, `p`, `i`, occurrence count
- [x] Delete (`d`), Print (`p`), Append (`a`), Insert (`i`), Change (`c`)
- [x] Transliterate (`y`)
- [x] Read/Write file (`r`, `w`)
- [x] Branch (`b`), Test (`t`, `T`)
- [x] Hold space operations (`h`, `H`, `g`, `G`, `x`)
- [x] Multiline (`N`, `P`, `D`)
- [x] In-place editing simulation (`-i`)
- [x] Multiple expressions (`-e`)
- [ ] Script file (`-f`)
- [x] Label resolution and branch execution
- [x] Quit (`q`, `Q`), List (`l`), Line number (`=`)
- [x] BRE/ERE support, empty-regex reuse
- [x] Iteration limit enforcement

### 3.3 awk (Full) ✅

- [x] AWK lexer and parser
- [x] Pattern-action rules (BEGIN, END, `/regex/`, expression)
- [x] Field splitting (`$0`, `$1`, ..., `$NF`)
- [x] Built-in variables (`NR`, `NF`, `FNR`, `FS`, `RS`, `OFS`, `ORS`, `SUBSEP`, `FILENAME`, `ENVIRON`, etc.)
- [x] String functions (`length`, `substr`, `index`, `split`, `gsub`, `sub`, `match`, `sprintf`, `printf`, `tolower`, `toupper`)
- [x] Math functions (`sin`, `cos`, `atan2`, `sqrt`, `int`, `log`, `exp`, `rand`, `srand`)
- [x] User-defined functions (with array parameter pass-by-reference)
- [x] Arrays (associative, `for-in` loops, `in` operator, `delete`)
- [x] Control flow (`if/else`, `for`, `while`, `do-while`, `for-in`, `break`, `continue`, `next`, `exit`, `return`)
- [x] Getline (bare, from file, from command pipe)
- [x] I/O: `print`, `printf`, `close()`, `system()`
- [x] Print/printf redirection to files (`>`, `>>`)
- [x] Ternary expressions, string concatenation
- [x] `OFMT` formatting
- [x] Iteration limit enforcement
- [x] Prototype-pollution hardening (for-in, function params, getline vars)

### 3.4 jq ✅ (Community Package: `bobzhang/moonjq`)

Migrated from handwritten evaluator to `bobzhang/moonjq` (MoonBit creator's package, commit `dbc5247`). Full jq language support provided by the community package, including:

- [x] Identity, field access, array/object indexing, slicing
- [x] Pipes, comma, object/array construction
- [x] Conditionals, comparison, logical operators
- [x] String interpolation
- [x] Try-catch, alternative (`//`), variable binding (`as $var`)
- [x] Reduce, foreach, recursive descent (`..`)
- [x] Path expressions, format strings
- [x] All core built-in functions
- [x] Iteration limit enforcement (via wrapper)

### 3.5 Remaining Text Commands ✅

- [x] `diff` (unified format, via `moonbit-community/piediff`)
- [x] `cmp` (byte-level file comparison)
- [x] `comm` (compare sorted files)
- [x] `join` (join on common field)
- [x] `column` (columnate)
- [x] `fold` (wrap lines)
- [x] `expand` / `unexpand` (tabs ↔ spaces)
- [x] `od` (octal dump)
- [x] `strings` (find printable strings)
- [x] `xargs` (build commands from stdin)
- [x] `split` (split files)

### 3.6 Hash & Encoding Commands ✅

- [x] `md5sum` (via `gmlewis/md5`)
- [x] `sha1sum` (via `gmlewis/sha1`)
- [x] `sha256sum` (via `shu-kitamura/sha256`)
- [x] `base64` (encode/decode, via `gmlewis/base64`)

### 3.7 Compression & Archives ✅

- [x] `gzip` (via `gmlewis/gzip` + `gmlewis/flate`)
- [x] `gunzip` (via `gmlewis/gzip`)
- [x] `zcat` (via `gmlewis/gzip`)
- [x] `tar` (via `bobzhang/tar`, pure-memory byte stream)

### 3.8 File System Commands ✅

- [x] `find` (with `-name`, `-type`, `-path`, `-exec`, `-maxdepth`, `-perm`, etc.)
- [x] `du` (disk usage, with `-h`, `-s`, `-d`)
- [x] `stat` (file status)
- [x] `file` (file type detection)
- [x] `tree` (directory tree display)
- [x] `ln` (symbolic links)
- [x] `readlink` (resolve symlinks)
- [x] `rmdir` (remove empty directories)
- [x] `chmod` (standalone command)

### 3.9 Shell Utility Commands ✅

- [x] `hostname`
- [x] `whoami`
- [x] `time` (command timing)
- [x] `timeout` (run with time limit)
- [x] `history` (command history)
- [x] `help` (help text)
- [x] `clear` (no-op in sandbox)

---

## Phase 4: Production Hardening 🔧

**Goal:** Production-ready release with comprehensive testing, security hardening, and advanced filesystem support.

### 4.1 OverlayFs — ⏸️ 由 AgentFS 替代

> **架构决策（2026-02-19）：** AI agent 主场景下，OverlayFs 的"宿主磁盘读层 + 内存写层"设计
> 被 AgentFS（Turso，SQLite-backed VFS）完整替代。AgentFS 天然提供 COW（`fs_whiteout` 表）、
> 持久化、可审计、可快照能力，且已有 just-bash 一等集成。详见 `docs/AGENTFS_ANALYSIS.md`。
>
> 若未来需支持本地开发工具场景（直接读宿主项目目录、不预装进 SQLite），可重新激活此计划。

- [ ] ~~FFI-backed disk read layer~~ → AgentFS SQLite 替代
- [ ] ~~Memory write layer~~ → AgentFS 写回 SQLite
- [ ] ~~Deleted file tracking~~ → AgentFS `fs_whiteout` 表
- [ ] ~~Path security validation~~ → AgentFS 内部处理
- [ ] ~~Size limits on disk reads~~ → AgentFS 内部处理
- [ ] AgentFS adapter in TypeScript wrapper layer (NEW)

### 4.2 MountableFs — ⏸️ 由 AgentFS 替代

> **架构决策（2026-02-19）：** AgentFS 单个 SQLite 即完整命名空间，无需多后端路由。
> MountableFs 的多挂载点设计在 AgentFS 模式下不再必要。详见 `docs/AGENTFS_ANALYSIS.md`。

- [ ] ~~Multi-mount point routing~~ → AgentFS 单一命名空间
- [ ] ~~Mount/unmount API~~ → 不再需要
- [ ] ~~Path normalization across mounts~~ → 不再需要

### 4.3 Network ✅

- [x] `curl` command implementation (via `globalThis.fetch` FFI)
- [x] `html-to-markdown` command
- [ ] URL prefix allowlist enforcement
- [ ] HTTP method restriction
- [ ] Redirect following with validation
- [ ] Timeout and response size limits

### 4.4 Defense-in-Depth 🔧

- [x] Prototype-pollution hardening (AWK for-in, function params, getline vars, builtins)
- [x] Execution limit enforcement (commands, loops, call depth, string size)
- [x] Pipefail semantics
- [ ] JS global patching (Function, eval, etc.)
- [ ] Audit mode
- [ ] Violation callbacks
- [ ] Configurable exclusions

### 4.5 Transform Plugins

- [ ] Plugin registration API
- [ ] AST visitor infrastructure
- [ ] Built-in plugins (CommandCollector, Tee)

### 4.6 Custom Commands ✅

- [x] Custom command bridge (`__moon_bash_custom__` via FFI)
- [x] User-provided command handlers (async, via TS wrapper)
- [ ] Lazy command loading
- [ ] Command filtering (`commands` option)

### 4.7 Testing ✅

- [x] Comparison test framework (record + replay, 26 fixture files)
- [x] Test fixtures against real bash output: **523/523 (100%)**
- [x] Bash spec tests: 136 cases (from Oils project)
- [x] AWK spec tests: 317 cases
- [x] grep/sed/jq spec tests
- [x] Security fuzz testing (grammar-based, flag-driven, malformed, coverage-boost generators)
- [x] Prototype-pollution test suite (6 files, comprehensive coverage)
- [x] Sandbox escape tests (command security, injection, dynamic execution, information disclosure)
- [x] Resource limit tests (DoS, memory, output size, pipeline limits)
- [x] Agent workflow tests: 13 real-world scenarios
- [x] OOM-safe batched test execution (`pnpm test:safe`)
- [ ] Edge case coverage (Unicode, binary, huge files)
- [ ] Performance benchmarks vs just-bash

### 4.8 Documentation & Release

- [ ] API reference documentation
- [ ] Migration guide from just-bash
- [ ] Performance comparison benchmarks
- [ ] npm publish (initial release)
- [ ] mooncakes.io publish

---

## Phase 5: Multi-Platform Expansion 🔧

**Goal:** Extend MoonBash beyond the npm ecosystem.

### 5.1 WASM Target

- [ ] `moon build --target wasm` configuration
- [ ] WASI interface layer
- [ ] Python bindings (`wasmtime` / `wasmer`)
- [ ] Rust bindings (`wasmtime` crate)
- [ ] PyPI publish (`pip install moon-bash`)

### 5.2 Browser Bundle

- [ ] Browser-specific build target
- [ ] IndexedDB-backed persistent VFS
- [ ] xterm.js integration example
- [ ] Web Worker support (off-main-thread execution)
- [ ] CSP-compatible (no eval, no dynamic imports)

### 5.3 Interactive Shell (REPL)

- [ ] Line editing and history
- [ ] Tab completion
- [ ] Prompt customization (`PS1`)
- [ ] CLI binary (`npx moon-bash`)

### 5.4 Advanced Features (Partially Complete)

- [x] `yq` (YAML processor, via `moonbit-community/yaml`)
- [x] `xan` (CSV processor, via `xunyoyo/NyaCSV`)
- [x] `csvlook` (CSV display, via `xunyoyo/NyaCSV`)
- [x] `rg` (ripgrep-compatible search, mapped to grep `-E`)
- [x] `python3` integration (optional, via Pyodide FFI bridge)
- [x] `sqlite3` integration (optional, via sql.js FFI bridge)
- [ ] `yq` extended: XML/TOML support

---

## Remaining Gaps (Low Priority)

Shell features not yet implemented, roughly ordered by impact:

| Feature | Category | Notes |
|---|---|---|
| Associative arrays (`declare -A`) | Variable system | `-A` attribute parsed but full data structure pending |
| `shopt` (shell options) | Builtin | e.g. `nullglob`, `extglob`, `globstar` |
| `trap` (signal handling) | Builtin | Would be simulated in sandbox |
| `pushd` / `popd` / `dirs` | Builtin | Directory stack |
| Process substitution (`<(cmd)`) | Expansion | Requires /dev/fd emulation |
| Extended globbing (`?(pat)`, etc.) | Expansion | Requires `shopt -s extglob` |
| Globstar (`**`) | Expansion | Requires `shopt -s globstar` |
| FD variables (`{var}>file`) | Redirection | Bash 4.1+ feature |
| `hash` / `enable` | Builtin | Command hash table management |
| grep `-f` / sed `-f` | Commands | Pattern/script file loading |
| CI/CD pipeline | Infra | GitHub Actions |
| AST `to_json()` | Debug | AST serialization |

---

## Community Packages Used

All binary/codec work is pure MoonBit (zero JS runtime dependencies). Community packages are compile-time only, fully inlined via DCE.

| Package | Used By | Purpose |
|---|---|---|
| `bobzhang/moonjq` | `jq` | Full jq language interpreter |
| `bobzhang/tar` | `tar` | Pure-memory tar archiver |
| `moonbit-community/piediff` | `diff`, `cmp` | Myers + Patience diff algorithms |
| `moonbit-community/yaml` | `yq` | YAML parser/emitter |
| `gmlewis/gzip` + `gmlewis/flate` | `gzip`, `gunzip`, `zcat` | Pure DEFLATE compression |
| `gmlewis/base64` | `base64` | Base64 encode/decode |
| `gmlewis/md5` | `md5sum` | MD5 hash |
| `gmlewis/sha1` | `sha1sum` | SHA-1 hash |
| `shu-kitamura/sha256` | `sha256sum` | SHA-256 hash |
| `xunyoyo/NyaCSV` | `xan`, `csvlook` | CSV parsing |
| `moonbitlang/regexp` | `grep`, `sed`, `awk` | Regular expressions |
| `justjavac/glob` | VFS glob | Glob pattern matching |

---

## Success Metrics

| Metric | Target | Current |
|---|---|---|
| API compatibility | 100% drop-in for just-bash | ✅ 100% |
| Bundle size (gzip) | <100 KB | TBD |
| Cold start time | <5 ms | TBD |
| Command coverage | 87 commands (matching just-bash) | ✅ 87 (100%) |
| Bash behavior accuracy | >95% (comparison tests) | ✅ 100% (523/523) |
| Spec test coverage | Oils bash + awk + sed + grep + jq | ✅ 473+ cases |
| Security test files | Comprehensive | ✅ 27 files |
| Agent workflow tests | Real-world scenarios | ✅ 13 scenarios |
| ReDoS vulnerability | 0 (VM-based regex) | ✅ 0 |
| Zero-day filesystem escapes | 0 (architectural guarantee) | ✅ 0 |
| FFI boundaries | Minimal (4 system primitives) | ✅ 4 (fetch, timer, VM, custom) |
