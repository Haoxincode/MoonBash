# MoonBash Development Roadmap

## Phase Overview

```
Phase 1: Foundation & MVP
  → Lexer, Parser, basic interpreter, InMemoryFs
  → 15 core commands
  → Build pipeline (MoonBit → JS → npm)

Phase 2: Shell Feature Completeness
  → Full variable expansion, arrays, functions
  → Control flow (if/for/while/case)
  → Redirections and pipes
  → 20 additional commands

Phase 3: Text Processing Powerhouse
  → grep, sed, awk (full implementations)
  → jq (JSON processor)
  → sort, cut, tr, diff, and remaining text commands

Phase 4: Production Hardening
  → OverlayFs, MountableFs
  → Network (curl)
  → Defense-in-depth
  → Comparison test suite against real bash
  → npm publish

Phase 5: Multi-Platform Expansion
  → WASM target for Python/Rust embedding
  → Browser bundle
  → Interactive shell (REPL)
```

---

## Phase 1: Foundation & MVP

**Goal:** Parse and execute simple bash scripts in-memory. Establish the full build pipeline from MoonBit source to npm package.

### 1.1 Project Setup

- [ ] Initialize MoonBit project (`moon.mod.json`)
- [ ] Configure JS backend (`moon.pkg.json` with `"targets": {"js": {...}}`)
- [ ] Set up TypeScript wrapper project (`package.json`, `tsconfig.json`)
- [ ] Configure build pipeline (`moon build --target js` → `tsup` bundle)
- [ ] Set up test infrastructure (MoonBit tests + TS integration tests)
- [ ] CI/CD pipeline (GitHub Actions)

### 1.2 AST Types

- [ ] Define all AST node types as MoonBit `enum`/`struct`
- [ ] Implement `to_string()`/`Show` for debug printing
- [ ] Implement `to_json()` for AST serialization (debugging/transform plugins)

### 1.3 Lexer

- [ ] Token type definition
- [ ] Basic word tokenization
- [ ] Quoted string handling (single, double, ANSI-C)
- [ ] Escape sequence handling
- [ ] Operator tokenization (`|`, `&&`, `||`, `;`, `&`)
- [ ] Redirection tokenization (`<`, `>`, `>>`, `<<`, `<<<`, etc.)
- [ ] Reserved word recognition (`if`, `then`, `else`, `fi`, `for`, `while`, etc.)
- [ ] Comment stripping (`#`)
- [ ] Heredoc content collection
- [ ] Parser limit enforcement (MAX_INPUT_SIZE, MAX_TOKENS)
- [ ] Comprehensive lexer tests

### 1.4 Parser

- [ ] Recursive descent parser structure
- [ ] Script (statement list) parsing
- [ ] Simple command parsing (words + redirections)
- [ ] Pipeline parsing (`cmd1 | cmd2`)
- [ ] List parsing (`&&`, `||`, `;`, `&`)
- [ ] Depth limit enforcement
- [ ] Parser error reporting with position info
- [ ] Parser tests

### 1.5 InMemoryFs

- [ ] `HashMap`-based file storage
- [ ] Path normalization (`.`, `..`, multiple slashes)
- [ ] Null byte validation
- [ ] `read_file`, `write_file`, `append_file`
- [ ] `exists`, `stat`
- [ ] `mkdir` (with recursive)
- [ ] `rm` (with recursive + force)
- [ ] `cp` (with recursive)
- [ ] `readdir`
- [ ] `symlink`, `readlink` (with loop detection)
- [ ] `chmod`
- [ ] Default layout creation (`/home/user`, `/bin`, `/tmp`)
- [ ] Filesystem tests

### 1.6 Basic Interpreter

- [ ] Execution context (env, cwd, stdin/stdout/stderr)
- [ ] Simple command execution
- [ ] Pipeline execution (stdout chaining)
- [ ] Execution limit tracking (command count)
- [ ] Exit code handling (`$?`)
- [ ] Basic variable expansion (`$VAR`, `${VAR}`)
- [ ] Command substitution (`$(cmd)`)
- [ ] Word splitting on IFS

### 1.7 Phase 1 Commands

| Command | Priority | Notes |
|---|---|---|
| `echo` | P0 | Builtin, handle `-n`, `-e` |
| `cat` | P0 | Read and concatenate files |
| `cd` | P0 | Builtin, change CWD |
| `pwd` | P0 | Builtin, print CWD |
| `ls` | P0 | List directory contents |
| `mkdir` | P0 | Create directories |
| `rm` | P0 | Remove files |
| `cp` | P0 | Copy files |
| `mv` | P0 | Move/rename files |
| `touch` | P0 | Create/update timestamps |
| `head` | P0 | First N lines |
| `tail` | P0 | Last N lines |
| `wc` | P0 | Count words/lines/chars |
| `true` | P0 | Return 0 |
| `false` | P0 | Return 1 |

### 1.8 TypeScript Wrapper

- [ ] `Bash` class with `exec()` method
- [ ] `ExecResult` / `BashExecResult` types
- [ ] `BashOptions` configuration
- [ ] `InitialFiles` support
- [ ] Bridge setup (global registration)
- [ ] Type definitions (`.d.ts`)

### 1.9 Build & Publish

- [ ] `moon build --target js` integration
- [ ] `tsup` bundling (ESM + types)
- [ ] npm package structure
- [ ] Verify drop-in compatibility with just-bash API

### 1.10 Ecosystem-First Delivery Checklist

- [ ] Create a command classification sheet (direct library / stdlib composition / state-machine / FFI).
- [ ] For every Phase 1 command, record the primary MoonBit API(s) and fallback path.
- [ ] Implement `cat`, `head`, `tail`, `wc` using shared line-stream helpers (`string` + `array`) rather than per-command parsing code.
- [ ] Implement `ls`, `cd`, `pwd`, `mkdir`, `touch`, `rm`, `cp`, `mv` on top of a single VFS trait and common path-normalization utility.
- [ ] Keep `echo`, `true`, `false` as builtin fast-path commands with zero allocator-heavy logic.
- [ ] Add tests that assert algorithm reuse behavior (for example: one shared sorter/path normalizer used by multiple commands).
- [ ] Add a merge gate: no new hand-rolled algorithm for a command if an approved package/stdlib path exists.

---

## Phase 2: Shell Feature Completeness

**Goal:** Support the full range of Bash control flow, expansions, and shell builtins.

### 2.1 Compound Commands

- [ ] `if / elif / else / fi`
- [ ] `for var in words; do ... done`
- [ ] C-style `for ((i=0; i<10; i++)); do ... done`
- [ ] `while condition; do ... done`
- [ ] `until condition; do ... done`
- [ ] `case word in pattern) ... ;; esac`
- [ ] Case terminators: `;;`, `;&`, `;;&`
- [ ] Subshell `( commands )`
- [ ] Group `{ commands; }`
- [ ] Loop control: `break`, `continue` (with depth)

### 2.2 Variable System

- [ ] Assignment (`VAR=value`)
- [ ] Local variables (`local VAR=value`)
- [ ] Export (`export VAR=value`)
- [ ] Readonly (`readonly VAR=value`)
- [ ] Unset (`unset VAR`)
- [ ] Indexed arrays (`arr=(a b c)`, `${arr[0]}`, `${arr[@]}`)
- [ ] Associative arrays (`declare -A map`, `${map[key]}`)
- [ ] Special variables (`$?`, `$#`, `$@`, `$*`, `$0`, `$$`, `$!`, `$RANDOM`, `$LINENO`)
- [ ] `declare` with attributes (`-i`, `-l`, `-u`, `-n`, `-r`, `-a`, `-A`)
- [ ] Namerefs (`declare -n ref=var`)

### 2.3 Full Expansion Engine

- [ ] Brace expansion (`{a,b,c}`, `{1..10}`, `{1..10..2}`)
- [ ] Tilde expansion (`~`, `~user`)
- [ ] Full parameter expansion (all `${VAR...}` forms)
- [ ] Arithmetic expansion (`$(( ))`)
- [ ] Process substitution (`<(cmd)`, `>(cmd)`)
- [ ] Quote removal
- [ ] Glob/pathname expansion (`*`, `?`, `[...]`)
- [ ] Extended globbing (`?(pat)`, `*(pat)`, `+(pat)`, `@(pat)`, `!(pat)`)
- [ ] Globstar (`**`)

### 2.4 Arithmetic

- [ ] Integer arithmetic (`+`, `-`, `*`, `/`, `%`)
- [ ] Comparison operators (`<`, `>`, `<=`, `>=`, `==`, `!=`)
- [ ] Logical operators (`&&`, `||`, `!`)
- [ ] Bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`)
- [ ] Ternary (`cond ? a : b`)
- [ ] Assignment operators (`=`, `+=`, `-=`, `*=`, `/=`, etc.)
- [ ] Pre/post increment/decrement (`++`, `--`)
- [ ] Parenthesized grouping

### 2.5 Conditionals

- [ ] `test` / `[` command
- [ ] `[[ ]]` extended test
- [ ] File tests (`-f`, `-d`, `-e`, `-r`, `-w`, `-x`, `-s`, `-L`, etc.)
- [ ] String tests (`-z`, `-n`, `=`, `!=`, `<`, `>`)
- [ ] Numeric tests (`-eq`, `-ne`, `-lt`, `-le`, `-gt`, `-ge`)
- [ ] Pattern matching in `[[ ]]` (`==`, `!=` with globs)
- [ ] Regex matching (`=~`)
- [ ] Logical operators (`-a`, `-o`, `!`, `&&`, `||`)

### 2.6 Redirections

- [ ] Input: `<`, `<<`, `<<<`, `<>`
- [ ] Output: `>`, `>>`, `>|`
- [ ] Stderr: `2>`, `2>>`, `&>`, `&>>`
- [ ] Duplication: `>&`, `<&`
- [ ] FD variables: `{var}>file`
- [ ] Multiple redirections per command
- [ ] `/dev/null`, `/dev/stdin`, `/dev/stdout`, `/dev/stderr`

### 2.7 Functions

- [ ] Function definition (`function name { }` and `name() { }`)
- [ ] Function invocation
- [ ] Positional parameters (`$1`, `$2`, ..., `$@`, `$*`, `$#`)
- [ ] `shift`
- [ ] Local variable scoping
- [ ] `return` with exit code
- [ ] Recursive call depth tracking

### 2.8 Shell Builtins

- [ ] `set` (options + positional params)
- [ ] `shopt` (shell options)
- [ ] `alias` / `unalias`
- [ ] `read` (with `-r`, `-p`, `-a`, `-d`, `-t`, `-n`)
- [ ] `printf` (full format string support)
- [ ] `source` / `.`
- [ ] `pushd` / `popd` / `dirs`
- [ ] `trap` (limited - signal handling simulation)
- [ ] `type` / `command`
- [ ] `hash`
- [ ] `enable`
- [ ] `eval`
- [ ] `exec` (redirection context only)

### 2.9 Phase 2 Commands

| Command | Notes |
|---|---|
| `env` | Print environment |
| `export` | Set env vars |
| `printenv` | Print env vars |
| `basename` | Path manipulation |
| `dirname` | Path manipulation |
| `which` | Command lookup |
| `seq` | Number sequences |
| `date` | Date formatting |
| `sleep` | Delay (via FFI) |
| `expr` | Expression evaluation |
| `tee` | Stdin to file + stdout |
| `sort` | Sort lines |
| `uniq` | Deduplicate lines |
| `grep` | Basic pattern matching |
| `cut` | Field extraction |
| `tr` | Character translation |
| `rev` | Reverse lines |
| `tac` | Reverse file |
| `paste` | Merge lines |
| `nl` | Number lines |

### 2.10 Ecosystem-First Expansion Checklist

- [ ] Implement `env`, `printenv`, `export`, `alias`, `unalias`, `history` on a unified session-state `HashMap` model.
- [ ] Implement `basename`, `dirname` as pure path-string transforms shared by parser expansions and command layer.
- [ ] Implement `sort`, `uniq`, `cut`, `tr`, `rev`, `tac`, `paste`, `nl` with composable iterator/text helpers, not command-specific ad hoc loops.
- [ ] Implement `seq`/`expr` on top of the math/eval helper module with strict numeric bounds.
- [ ] Implement `date` with `@moonbitlang/x/time` adapter; keep output format compatibility tests in comparison suite.
- [ ] Implement `sleep` via FFI timer bridge only; enforce cancellation + timeout behavior in security tests.
- [ ] Before Phase 3, run a reuse audit documenting which commands still require custom engines (`awk` and parser-related paths).

---

## Phase 3: Text Processing Powerhouse

**Goal:** Implement the complex text processing commands that make the sandbox useful for real data pipeline work.

### 3.1 grep (Full)

- [ ] BRE (Basic Regular Expressions)
- [ ] ERE (Extended Regular Expressions) - `-E`
- [ ] Fixed string matching - `-F`
- [ ] All flags (`-i`, `-v`, `-c`, `-n`, `-l`, `-L`, `-w`, `-x`, `-q`)
- [ ] Context lines (`-A`, `-B`, `-C`)
- [ ] Recursive search (`-r`, `-R`)
- [ ] Multiple patterns (`-e`)
- [ ] Pattern file (`-f`)
- [ ] Integration with `@regexp` library

### 3.2 sed (Full)

- [ ] Address types (line number, `$`, `/regex/`, range, step)
- [ ] Substitute command (`s/pattern/replacement/flags`)
- [ ] Delete (`d`), Print (`p`), Append (`a`), Insert (`i`), Change (`c`)
- [ ] Transliterate (`y`)
- [ ] Read/Write file (`r`, `w`)
- [ ] Branch (`b`), Test (`t`, `T`)
- [ ] Hold space operations (`h`, `H`, `g`, `G`, `x`)
- [ ] Multiline (`N`, `P`, `D`)
- [ ] In-place editing simulation (`-i`)
- [ ] Multiple expressions (`-e`)
- [ ] Script file (`-f`)
- [ ] Iteration limit enforcement

### 3.3 awk (Full)

- [ ] AWK lexer and parser
- [ ] Pattern-action rules (BEGIN, END, `/regex/`, expression)
- [ ] Field splitting (`$0`, `$1`, ..., `$NF`)
- [ ] Built-in variables (`NR`, `NF`, `FS`, `RS`, `OFS`, `ORS`, `FILENAME`, etc.)
- [ ] String functions (`length`, `substr`, `index`, `split`, `gsub`, `sub`, `match`, `sprintf`, `printf`, `tolower`, `toupper`)
- [ ] Math functions (`sin`, `cos`, `sqrt`, `int`, `log`, `exp`, `rand`, `srand`)
- [ ] User-defined functions
- [ ] Arrays (associative)
- [ ] Control flow (`if/else`, `for`, `while`, `do-while`, `break`, `continue`)
- [ ] Getline
- [ ] Multiple input files
- [ ] Iteration limit enforcement

### 3.4 jq (Full)

- [ ] JQ filter lexer and parser
- [ ] Identity (`.`), field access (`.field`, `.["field"]`)
- [ ] Array/object index (`.[0]`, `.[-1]`, `.[2:5]`)
- [ ] Pipe (`|`), comma (`,`)
- [ ] Object/array construction (`{...}`, `[...]`)
- [ ] Conditionals (`if-then-elif-else-end`)
- [ ] Comparison and logical operators
- [ ] String interpolation (`\(expr)`)
- [ ] Try-catch
- [ ] Alternative (`//`)
- [ ] Variable binding (`as $var`)
- [ ] Reduce (`reduce`)
- [ ] `foreach`, `limit`, `first`, `last`, `nth`
- [ ] Recursive descent (`..`)
- [ ] Path expressions (`path()`, `getpath()`, `setpath()`, `delpaths()`)
- [ ] Format strings (`@base64`, `@csv`, `@tsv`, `@html`, `@json`, `@text`, `@uri`)
- [ ] All built-in functions (`length`, `keys`, `values`, `has`, `in`, `map`, `select`, `empty`, `error`, `type`, `sort_by`, `group_by`, `unique_by`, `flatten`, `range`, `floor`, `ceil`, `round`, `tostring`, `tonumber`, `ascii_downcase`, `ascii_upcase`, `ltrimstr`, `rtrimstr`, `startswith`, `endswith`, `split`, `join`, `test`, `match`, `capture`, `gsub`, `sub`, `scan`, `env`, `builtins`, `input`, `inputs`, `debug`, `stderr`, `halt`, `halt_error`, etc.)
- [ ] Iteration limit enforcement

### 3.5 Remaining Text Commands

- [ ] `diff` (unified, context formats)
- [ ] `comm` (compare sorted files)
- [ ] `join` (join on common field)
- [ ] `column` (columnate)
- [ ] `fold` (wrap lines)
- [ ] `expand` / `unexpand` (tabs ↔ spaces)
- [ ] `od` (octal dump)
- [ ] `strings` (find printable strings)
- [ ] `xargs` (build commands from stdin)
- [ ] `split` (split files)

### 3.6 Hash Commands

- [ ] `md5sum`
- [ ] `sha1sum`
- [ ] `sha256sum`
- [ ] `base64` (encode/decode)

### 3.7 Remaining Commands

- [ ] `find` (with `-name`, `-type`, `-path`, `-exec`, `-maxdepth`, etc.)
- [ ] `du` (disk usage)
- [ ] `stat` (file status)
- [ ] `file` (file type detection)
- [ ] `tree` (directory tree)
- [ ] `ln` (symbolic links)
- [ ] `readlink`
- [ ] `rmdir`
- [ ] `chmod`
- [ ] `hostname`
- [ ] `whoami`
- [ ] `time`
- [ ] `timeout`
- [ ] `history`
- [ ] `help`
- [ ] `clear`

---

## Phase 4: Production Hardening

**Goal:** Production-ready release with comprehensive testing, security hardening, and advanced filesystem support.

### 4.1 OverlayFs

- [ ] FFI-backed disk read layer
- [ ] Memory write layer
- [ ] Deleted file tracking
- [ ] Path security validation
- [ ] Size limits on disk reads

### 4.2 MountableFs

- [ ] Multi-mount point routing
- [ ] Mount/unmount API
- [ ] Path normalization across mounts

### 4.3 Network

- [ ] `curl` command implementation
- [ ] URL prefix allowlist enforcement
- [ ] HTTP method restriction
- [ ] Redirect following with validation
- [ ] Timeout and response size limits
- [ ] `html-to-markdown` command

### 4.4 Defense-in-Depth

- [ ] JS global patching (Function, eval, etc.)
- [ ] Audit mode
- [ ] Violation callbacks
- [ ] Configurable exclusions

### 4.5 Transform Plugins

- [ ] Plugin registration API
- [ ] AST visitor infrastructure
- [ ] Built-in plugins (CommandCollector, Tee)

### 4.6 Custom Commands

- [ ] `defineCommand` helper
- [ ] Lazy command loading
- [ ] Command filtering (`commands` option)

### 4.7 Testing

- [ ] Comparison test framework (record + replay)
- [ ] Test fixtures against real bash output
- [ ] Security fuzz testing
- [ ] Edge case coverage (Unicode, binary, huge files)
- [ ] Performance benchmarks vs just-bash

### 4.8 Documentation & Release

- [ ] API reference documentation
- [ ] Migration guide from just-bash
- [ ] Performance comparison benchmarks
- [ ] npm publish (initial release)
- [ ] mooncakes.io publish

---

## Phase 5: Multi-Platform Expansion

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

### 5.4 Advanced Features

- [ ] `yq` (YAML/XML/TOML processor)
- [ ] `xan` (CSV processor)
- [ ] `rg` (ripgrep-compatible search)
- [ ] Compression (`gzip`, `gunzip`, `zcat`, `tar`)
- [ ] `python3` integration (optional, via Pyodide)

---

## Success Metrics

| Metric | Target |
|---|---|
| API compatibility | 100% drop-in for just-bash |
| Bundle size (gzip) | <100 KB |
| Cold start time | <5 ms |
| Command coverage | 80+ commands |
| Bash behavior accuracy | >95% (comparison tests) |
| ReDoS vulnerability | 0 (VM-based regex) |
| Zero-day filesystem escapes | 0 (architectural guarantee) |
