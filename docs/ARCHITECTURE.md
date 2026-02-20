# MoonBash Architecture Design

## 1. Design Principles

1. **Correctness First** - Behavior must match real Bash. Use comparison tests against actual bash output.
2. **Safety by Construction** - MoonBit's ADT and exhaustive pattern matching eliminate entire classes of bugs at compile time.
3. **Zero Runtime Dependencies** - The compiled JS output must have no external npm dependencies.
4. **API Compatibility** - The TypeScript wrapper must expose an identical API to `just-bash`.
5. **Incremental Migration** - Architecture must support incremental command implementation with fallback mechanisms.

Status note (as of 2026-02-19): core architecture and command coverage are complete; compatibility hardening is still in progress. For latest pass/fail truth, use `docs/TEST_STATUS_2026-02-19.md` and `docs/ROADMAP.md`.

## 1.1 Ecosystem-First Implementation Strategy

MoonBash follows an ecosystem-first implementation policy: reuse official MoonBit and vetted community packages before introducing custom algorithms. The command plan is split into four lanes:

1. **Direct library takeover** - Regex/JSON/codec/hash/time-heavy commands should bind directly to mature packages.
2. **Core stdlib composition** - Most text utilities should be implemented via `core/string`, `core/array`, `core/iter`, and `core/hash*` primitives.
3. **Data-structure state machine** - env/alias/history and VFS commands should be modeled as deterministic in-memory state transitions.
4. **FFI boundary commands** - network, timers, and heavyweight runtimes should stay in host JS via `extern "js"` bridges.

This keeps parser/interpreter code small and auditable while preserving performance and security properties (notably regex safety and bounded execution). Full mapping and package guidance live in `docs/ECOSYSTEM_COMMAND_MAPPING.md`.

## 2. "巨核与薄壳" Architecture (Fat Kernel & Thin Shell)

所有与"物理 I/O"无关的纯计算、纯解析任务，100% 收敛回 MoonBit 内部。FFI 边界压缩到 4 个系统原语。

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: TypeScript API Facade  (<100 lines glue)           │
│                                                             │
│  class Bash { exec(), getFs(), ... }                        │
│  class Sandbox { ... }                                      │
│                                                             │
│  Purpose: API-surface compatibility with just-bash          │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: FFI Thin Shell  (4 system primitives only)         │
│                                                             │
│  Network:     globalThis.fetch       (curl)                 │
│  Timers:      setTimeout/Date.now()  (sleep/timeout)        │
│  Heavy VMs:   Pyodide/sql.js         (python3/sqlite3)      │
│  Disk I/O:    AgentFS adapter        (wrapper sync path)    │
│                                                             │
│  Purpose: Minimal side-effect bridge, zero business logic   │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: MoonBit Fat Kernel  (all pure computation)         │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐        │
│  │  Lexer   │→ │  Parser  │→ │    Interpreter     │        │
│  └──────────┘  └──────────┘  └────────────────────┘        │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐        │
│  │   AST    │  │ Expansion│  │   Command Registry │        │
│  │  Types   │  │  Engine  │  │   (87 commands)    │        │
│  └──────────┘  └──────────┘  └────────────────────┘        │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐        │
│  │awk/sed/jq│  │ tar/diff │  │   InMemoryFs       │        │
│  │Micro VMs │  │ gzip/b64 │  │   (pure MoonBit)   │        │
│  └──────────┘  └──────────┘  └────────────────────┘        │
│                                                             │
│  Purpose: Parsing, evaluation, commands, algorithms, VFS    │
│  Compiled: ~245 KB gzip (997 KB min), zero npm dependencies │
└─────────────────────────────────────────────────────────────┘
```

## 3. Core Pipeline

### 3.1 Lexer

The lexer converts raw Bash script text into a stream of tokens.

**Implementation Strategy:** Use MoonBit's `lexmatch` syntax for pattern-based tokenization.

```
Input: echo "hello $USER" | grep hello > output.txt
  ↓
Tokens: [WORD("echo"), WORD("hello $USER"), PIPE, WORD("grep"),
         WORD("hello"), REDIRECT_OUT, WORD("output.txt")]
```

**Token Types:**

```moonbit
enum Token {
  // Literals
  Word(String)
  Number(Int)
  AssignmentWord(String, String)  // name=value

  // Operators
  Pipe                    // |
  PipeAnd                 // |&
  And                     // &&
  Or                      // ||
  Semi                    // ;
  Ampersand               // &
  Newline

  // Redirections
  RedirectIn              // <
  RedirectOut             // >
  RedirectAppend          // >>
  RedirectClobber         // >|
  HereDoc                 // <<
  HereDocStrip            // <<-
  HereString              // <<<
  DupIn                   // <&
  DupOut                  // >&
  RedirectInOut           // <>
  RedirectAndOut           // &>
  RedirectAndAppend        // &>>

  // Grouping
  LeftParen               // (
  RightParen              // )
  LeftBrace               // {
  RightBrace              // }

  // Compound
  DoubleBracketOpen       // [[
  DoubleBracketClose      // ]]

  // Reserved words
  If | Then | Elif | Else | Fi
  For | While | Until | Do | Done
  Case | Esac | In
  Function
  Select
  Bang                    // !
  Time

  // Special
  EOF
  FdNumber(Int)           // File descriptor number before redirect
}
```

### 3.2 Parser

Recursive descent parser that converts token stream into a strongly-typed AST.

**AST Node Types:**

```moonbit
/// Top-level script
struct Script {
  statements : Array[Statement]
}

/// A statement is a pipeline with optional next-statement operator
enum Statement {
  Pipeline(Pipeline)
  AndList(Pipeline, Statement)     // cmd1 && cmd2
  OrList(Pipeline, Statement)      // cmd1 || cmd2
  Background(Pipeline)             // cmd &
  Sequence(Pipeline, Statement)    // cmd1 ; cmd2
}

/// A pipeline connects commands via pipes
struct Pipeline {
  negated : Bool                   // ! prefix
  commands : Array[Command]
  pipe_stderr : Bool               // |& instead of |
}

/// Command variants
enum Command {
  Simple(SimpleCommand)
  Compound(CompoundCommand)
  FunctionDef(FunctionDef)
}

struct SimpleCommand {
  assignments : Array[Assignment]
  words : Array[Word]
  redirections : Array[Redirection]
}

enum CompoundCommand {
  If(IfClause)
  For(ForClause)
  CStyleFor(CStyleForClause)
  While(WhileClause)
  Until(UntilClause)
  Case(CaseClause)
  Subshell(Script)
  Group(Script)
  ArithmeticCommand(ArithExpr)
  ConditionalCommand(CondExpr)
}

struct IfClause {
  condition : Script
  then_branch : Script
  elif_branches : Array[(Script, Script)]
  else_branch : Script?
}

struct ForClause {
  var_name : String
  words : Array[Word]?    // None = "$@"
  body : Script
}

struct CStyleForClause {
  init : ArithExpr
  condition : ArithExpr
  update : ArithExpr
  body : Script
}

struct WhileClause {
  condition : Script
  body : Script
}

struct UntilClause {
  condition : Script
  body : Script
}

struct CaseClause {
  word : Word
  items : Array[CaseItem]
}

struct CaseItem {
  patterns : Array[Word]
  body : Script
  terminator : CaseTerminator  // ;; | ;& | ;;&
}

enum CaseTerminator {
  Break        // ;;
  Fallthrough  // ;&
  Continue     // ;;&
}

struct FunctionDef {
  name : String
  body : CompoundCommand
  redirections : Array[Redirection]
}
```

**Word and Expansion Types:**

```moonbit
/// A word is composed of parts that may need expansion
struct Word {
  parts : Array[WordPart]
}

enum WordPart {
  Literal(String)
  SingleQuoted(String)
  DoubleQuoted(Array[WordPart])
  Variable(String)
  ParameterExpansion(ParamExpansion)
  CommandSubstitution(String)
  ArithmeticExpansion(ArithExpr)
  BraceExpansion(Array[Array[WordPart]])
  TildePrefix(String)
  Glob(GlobPattern)
}

enum ParamExpansion {
  Simple(String)                              // $VAR
  Default(String, Word, Bool)                 // ${VAR:-word} / ${VAR-word}
  Assign(String, Word, Bool)                  // ${VAR:=word} / ${VAR=word}
  Error(String, Word?, Bool)                  // ${VAR:?word} / ${VAR?word}
  Alternative(String, Word, Bool)             // ${VAR:+word} / ${VAR+word}
  Length(String)                              // ${#VAR}
  Substring(String, ArithExpr, ArithExpr?)    // ${VAR:offset:length}
  PrefixRemove(String, Word, Bool)            // ${VAR#pat} / ${VAR##pat}
  SuffixRemove(String, Word, Bool)            // ${VAR%pat} / ${VAR%%pat}
  Replace(String, Word, Word?, ReplaceMode)   // ${VAR/pat/str}
  Uppercase(String, Word?, Bool)              // ${VAR^pat} / ${VAR^^pat}
  Lowercase(String, Word?, Bool)              // ${VAR,pat} / ${VAR,,pat}
  Indirection(String)                         // ${!VAR}
}

enum ReplaceMode {
  First       // ${VAR/pat/str}
  All         // ${VAR//pat/str}
  Prefix      // ${VAR/#pat/str}
  Suffix      // ${VAR/%pat/str}
}
```

**Redirection Types:**

```moonbit
struct Redirection {
  fd : Int?               // File descriptor (None = default)
  fd_var : String?        // {varname} for fd variable
  op : RedirectOp
  target : Word
}

enum RedirectOp {
  Input           // <
  Output          // >
  Append          // >>
  Clobber         // >|
  InputOutput     // <>
  HereDoc(Bool)   // << (strip_tabs: Bool)
  HereString      // <<<
  DupInput        // <&
  DupOutput       // >&
  AndOutput       // &>
  AndAppend       // &>>
}
```

### 3.3 Interpreter (Evaluator)

Tree-walking interpreter that executes the AST with full state management.

**Execution Context:**

```moonbit
struct ExecContext {
  // Environment
  mut env : @hashmap.HashMap[String, String]
  mut exported : @hashset.HashSet[String]
  mut cwd : String

  // Functions
  mut functions : @hashmap.HashMap[String, FunctionDef]

  // Shell options
  mut options : ShellOptions

  // I/O
  mut stdin : String
  mut stdout : @buffer.Buffer
  mut stderr : @buffer.Buffer
  mut file_descriptors : @hashmap.HashMap[Int, String]

  // Control flow
  mut exit_code : Int
  mut should_exit : Bool
  mut loop_depth : Int
  mut break_count : Int
  mut continue_count : Int
  mut return_requested : Bool

  // Limits
  limits : ExecutionLimits
  mut command_count : Int
  mut call_depth : Int

  // External callbacks (FFI)
  fs : FsCallbacks
  network : NetworkCallbacks?
  sleep_fn : ((Int) -> Unit)?
  trace_fn : ((TraceEvent) -> Unit)?
}

struct ShellOptions {
  mut errexit : Bool       // set -e
  mut nounset : Bool       // set -u
  mut pipefail : Bool      // set -o pipefail
  mut noclobber : Bool     // set -C
  mut xtrace : Bool        // set -x
  mut noglob : Bool        // set -f
  mut allexport : Bool     // set -a
}

struct ExecutionLimits {
  max_call_depth : Int           // Default: 100
  max_command_count : Int        // Default: 10000
  max_loop_iterations : Int      // Default: 10000
  max_string_length : Int        // Default: 10MB
  max_array_elements : Int       // Default: 100000
  max_heredoc_size : Int         // Default: 10MB
  max_substitution_depth : Int   // Default: 50
  max_glob_operations : Int      // Default: 100000
  max_awk_iterations : Int       // Default: 10000
  max_sed_iterations : Int       // Default: 10000
  max_jq_iterations : Int        // Default: 10000
}
```

**Execution Flow:**

```
execute_script(Script, ExecContext) -> ExecResult
  ├── for each Statement:
  │   ├── execute_statement(Statement, ctx)
  │   │   ├── AndList: execute left, if success execute right
  │   │   ├── OrList:  execute left, if fail execute right
  │   │   ├── Sequence: execute left, then right
  │   │   └── Background: execute and don't wait
  │   └── check exit/break/continue/return flags
  │
  └── execute_pipeline(Pipeline, ctx) -> ExecResult
      ├── Single command: execute_command directly
      └── Multiple commands: chain stdin/stdout
          ├── cmd1.stdout -> cmd2.stdin
          ├── cmd2.stdout -> cmd3.stdin
          └── return last exit code (or first failure if pipefail)

execute_command(Command, ctx) -> ExecResult
  ├── Simple:
  │   ├── expand_words(words, ctx)     // Variable/glob/brace expansion
  │   ├── apply_redirections(redirections, ctx)
  │   ├── lookup_command(name)
  │   │   ├── Check aliases
  │   │   ├── Check functions
  │   │   ├── Check builtins (cd, export, etc.)
  │   │   └── Check registered commands
  │   └── execute with args and context
  │
  ├── Compound:
  │   ├── If:     evaluate condition, execute branch
  │   ├── For:    iterate over expanded words
  │   ├── While:  loop while condition succeeds
  │   ├── Case:   match word against patterns
  │   ├── Subshell: clone context, execute, discard changes
  │   └── Group:  execute in current context
  │
  └── FunctionDef: register function in ctx.functions
```

### 3.4 Expansion Engine

The expansion engine processes Word nodes through multiple expansion phases in order:

```
1. Brace Expansion      {a,b,c} -> a b c
       ↓
2. Tilde Expansion      ~/path -> /home/user/path
       ↓
3. Parameter Expansion   $VAR, ${VAR:-default}, ${VAR#prefix}
       ↓
4. Command Substitution  $(command), `command`
       ↓
5. Arithmetic Expansion  $((1 + 2))
       ↓
6. Word Splitting        Split on $IFS (default: space/tab/newline)
       ↓
7. Pathname Expansion    *.txt -> file1.txt file2.txt
       ↓
8. Quote Removal         Remove unescaped quotes
```

### 3.5 Command Registry

Commands are organized by category with lazy initialization:

```moonbit
enum CommandCategory {
  FileOps        // cat, cp, ls, mkdir, mv, rm, etc.
  TextProcessing // awk, grep, sed, sort, cut, etc.
  DataProcessing // jq, yq, xan
  Compression    // gzip, tar
  Navigation     // cd, pwd, basename, dirname
  ShellUtils     // alias, date, seq, sleep, etc.
  Network        // curl, html-to-markdown
}

trait CommandImpl {
  name(Self) -> String
  execute(Self, Array[String], CommandContext) -> ExecResult
}
```

## 4. Module Layout

```
moon-bash/
├── src/
│   ├── lib/                               # MoonBit core library (~14K lines)
│   │   ├── ast/                           # AST type definitions
│   │   │   └── types.mbt                 # All AST node types (enum/struct)
│   │   ├── lexer/                         # Tokenizer
│   │   │   ├── lexer.mbt                 # Token types and lexer logic
│   │   │   └── lexer_test.mbt            # Lexer unit tests
│   │   ├── parser/                        # Recursive descent parser
│   │   │   ├── parser.mbt               # Main parser entry + pipelines/lists
│   │   │   ├── compound.mbt             # Compound command parsing (if/for/while/case)
│   │   │   ├── word.mbt                 # Word/expansion/arithmetic parsing
│   │   │   └── parser_test.mbt          # Parser tests
│   │   ├── interpreter/                   # AST evaluator (~6K lines)
│   │   │   ├── interpreter.mbt          # ExecContext definition, entry point
│   │   │   ├── interpreter_execution.mbt # Command/pipeline/redirection execution
│   │   │   ├── expansion.mbt            # Runtime word expansion engine
│   │   │   ├── control_flow.mbt         # if/for/while/until/case evaluation
│   │   │   ├── builtins_dispatch.mbt    # Builtin name → handler routing
│   │   │   ├── builtins_state_flow.mbt  # exit/return/break/continue/export/set/local
│   │   │   ├── builtins_io_meta.mbt     # read/printf/eval/source/test/[[
│   │   │   ├── builtins_path_env.mbt    # basename/dirname/seq/env/printenv/which/date
│   │   │   ├── builtins_text.mbt        # sort/uniq/cut/tee/rev/nl/fold/expand/paste/column/join
│   │   │   ├── builtins_text_transform.mbt # tr
│   │   │   ├── builtins_search.mbt      # grep/sed/xargs
│   │   │   ├── helpers.mbt             # General helpers (glob, pattern, arithmetic)
│   │   │   ├── helpers_text.mbt         # Text processing helpers (field extraction, etc.)
│   │   │   └── helpers_search.mbt       # Grep/sed helpers (regex, address matching)
│   │   ├── commands/                      # Registered external commands (~6K lines)
│   │   │   ├── registry.mbt             # Command name → handler dispatch
│   │   │   ├── file_ops.mbt             # ls/mkdir/rm/cp/mv/touch/find/cat
│   │   │   ├── text.mbt                 # head/tail/wc
│   │   │   ├── shell.mbt               # echo/cd/pwd/true/false
│   │   │   ├── awk_jq.mbt              # AWK interpreter + jq JSON engine
│   │   │   └── strings_split_tar.mbt   # strings/split/tar
│   │   ├── fs/                            # Virtual filesystem
│   │   │   ├── types.mbt               # VFS trait definitions
│   │   │   ├── inmemory.mbt            # InMemoryFs (HashMap-based)
│   │   │   ├── path.mbt               # Path normalization
│   │   │   └── glob.mbt               # Glob pattern matching
│   │   ├── regex/                         # Regex wrapper
│   │   │   └── regex.mbt              # @moonbitlang/core/regexp thin wrapper
│   │   ├── ffi/                           # JS interop (placeholder)
│   │   │   └── ffi.mbt                # FFI declarations
│   │   └── entry/                         # Entry point bridge
│   │       └── entry.mbt              # execute_with_state() FFI export
│   │
│   ├── wrapper/                           # TypeScript API layer
│   │   ├── index.ts                      # Main entry: class Bash, class Sandbox
│   │   └── types.ts                      # TypeScript type definitions
│   │
│   └── moon.mod.json                      # MoonBit module config
│
├── tests/
│   ├── comparison/                        # Bash behavior comparison tests (523 cases)
│   │   └── fixtures/                     # 26 JSON fixtures with real bash outputs
│   ├── spec/                              # Specification tests
│   │   ├── bash/                         # 136+ bash spec tests (from Oils)
│   │   ├── awk/                          # AWK spec tests
│   │   ├── sed/                          # sed spec tests
│   │   ├── grep/                         # grep spec tests
│   │   └── jq/                           # jq spec tests
│   ├── security/                          # Security & fuzzing tests
│   └── agent-examples/                    # 13 AI agent workflow scenarios
│
├── docs/                                  # Design documentation
├── package.json                           # NPM package config
├── tsconfig.json                          # TypeScript config
└── tsup.config.ts                         # Bundling config
```

## 5. Data Flow Example

A complete trace of `echo "hello $USER" > output.txt`:

```
1. INPUT
   "echo \"hello $USER\" > output.txt"

2. LEXER
   [Word("echo"), Word("hello $USER"), RedirectOut, Word("output.txt")]

3. PARSER
   Script {
     statements: [
       Pipeline {
         commands: [
           Simple {
             words: [
               Word[Literal("echo")],
               Word[DoubleQuoted([
                 Literal("hello "),
                 Variable("USER")
               ])]
             ],
             redirections: [
               Redirection {
                 fd: None,   // defaults to stdout (1)
                 op: Output,
                 target: Word[Literal("output.txt")]
               }
             ]
           }
         ]
       }
     ]
   }

4. EXPANSION
   words[0] -> "echo"
   words[1] -> "hello agent"  (USER="agent" from env)
   redirect target -> "output.txt"

5. COMMAND LOOKUP
   "echo" -> Builtin(EchoCommand)

6. EXECUTION
   EchoCommand.execute(["hello agent"], ctx)
   -> stdout = "hello agent\n"

7. REDIRECTION
   Write "hello agent\n" to file "output.txt" via VFS

8. RESULT
   ExecResult { stdout: "", stderr: "", exit_code: 0 }
   (stdout captured by redirect, not returned)
```

## 6. Compilation & Build Pipeline

```
MoonBit Source (.mbt)
       │
       ▼
moon build --target js
       │
       ▼
Pure JavaScript (moon_bash-core.js)
       │
       ▼
TypeScript Wrapper (src/wrapper/*.ts)
       │
       ▼
tsup / esbuild bundling
       │
       ├── dist/index.js        (Node.js ESM)
       ├── dist/index.d.ts      (Type definitions)
       └── dist/browser.js      (Browser ESM)
       │
       ▼
npm publish moon-bash
```

### 6.1 Build Size Analysis (2026-02-19 Measured)

MoonBit compiles to a single JS file with fully qualified names (e.g. `$moonbitlang$core$array$Array$push`) to avoid scope collisions. This inflates raw text size but compresses extremely well through standard JS tooling.

**Full pipeline measurements** (87 commands including awk/sed/jq/tar/diff/gzip interpreters):

| Stage | Size | vs Raw | Notes |
|-------|------|--------|-------|
| debug (`moon build --target js`) | 4,796,827 bytes (4.6 MB) | 100% | Includes `.js.map` source map (3.5 MB separate) |
| release (`moon build --target js --release`) | 4,342,023 bytes (4.2 MB) | 90.5% | DCE + inlining; no source map |
| release + minify (`esbuild --minify`) | 1,021,156 bytes (997 KB) | 21.3% | Name mangling crushes FQNs to single letters |
| release + minify + gzip | 251,147 bytes (245 KB) | 5.2% | Realistic network transfer size |

**Why `--release` only saves ~9.5%:**
Unlike C/Rust where debug builds embed DWARF symbols and panic stacks directly in the binary, MoonBit's debug mode is already lean — debug info lives in a separate `.js.map` file. The `--release` flag triggers additional DCE and inlining but the core computation code is already tightly generated.

**Why minify is so effective (4.2 MB → 997 KB, -76%):**
The raw JS output is dominated by repeated fully qualified identifiers like `$Haoxincode$MoonBash$awk_execute_action$current_fields`. These 30-40 character names appear tens of thousands of times across the codebase. `esbuild --minify` crushes them all to single-letter variables and strips whitespace.

**Why gzip compresses further (997 KB → 245 KB, -75%):**
Minified JS has high pattern repetition (single-letter variables, repeated structural patterns), making it extremely compressible. This is a fundamental advantage over Wasm — `.wasm` binaries are dense machine code with high information entropy, so they barely compress (typically only 20-30% reduction via gzip).

**Deployment target compatibility:**

| Platform | Limit | Fits? |
|----------|-------|-------|
| Vercel Serverless Functions | 50 MB uncompressed | Yes |
| Vercel Edge Functions | 1-4 MB (plan-dependent) | Yes (997 KB minified) |
| Cloudflare Workers (free) | 1 MB compressed | Yes (245 KB gzip) |
| Cloudflare Workers (paid) | 10 MB compressed | Yes |
| Browser `<script>` | N/A (network cost) | 245 KB transfer |

**JS vs Wasm tradeoff for this use case:**
An equivalent Rust→Wasm build would produce ~600-800 KB after `wasm-opt -Oz`, but Wasm cannot be minified (no variable renaming) and compresses poorly (~300 KB+ gzip). Additionally, Wasm incurs FFI overhead for every string crossing the JS↔Wasm boundary (deep copy required), while MoonBit's JS output operates on native V8 strings with zero copy cost. Wasm also requires async `WebAssembly.instantiate()`, preventing synchronous cold start.
