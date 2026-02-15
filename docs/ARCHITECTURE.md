# MoonBash Architecture Design

## 1. Design Principles

1. **Correctness First** - Behavior must match real Bash. Use comparison tests against actual bash output.
2. **Safety by Construction** - MoonBit's ADT and exhaustive pattern matching eliminate entire classes of bugs at compile time.
3. **Zero Runtime Dependencies** - The compiled JS output must have no external npm dependencies.
4. **API Compatibility** - The TypeScript wrapper must expose an identical API to `just-bash`.
5. **Incremental Migration** - Architecture must support incremental command implementation with fallback mechanisms.

## 2. Three-Layer Architecture

MoonBash uses a three-layer architecture to separate concerns between the MoonBit core engine, the JS interop boundary, and the TypeScript-facing API.

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: TypeScript API Facade                              │
│                                                             │
│  class Bash { exec(), getFs(), ... }                        │
│  class Sandbox { ... }                                      │
│  Type definitions (.d.ts)                                   │
│                                                             │
│  Purpose: 100% API compatibility with just-bash             │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: FFI Boundary (extern "js")                         │
│                                                             │
│  FS callbacks:  read_file, write_file, stat, ...            │
│  Network:       fetch_url                                   │
│  Async bridge:  MoonBit async <-> JS Promise                │
│  Regex bridge:  (fallback to JS RegExp if needed)           │
│                                                             │
│  Purpose: Side-effect isolation, async bridging             │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: MoonBit Core Engine (Pure Logic)                   │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐        │
│  │  Lexer   │→ │  Parser  │→ │    Interpreter     │        │
│  └──────────┘  └──────────┘  └────────────────────┘        │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐        │
│  │   AST    │  │ Expansion│  │   Command Registry │        │
│  │  Types   │  │  Engine  │  │   (80+ commands)   │        │
│  └──────────┘  └──────────┘  └────────────────────┘        │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐        │
│  │ Builtins │  │  Regex   │  │   InMemoryFs       │        │
│  │ (cd,set) │  │  Engine  │  │   (pure MoonBit)   │        │
│  └──────────┘  └──────────┘  └────────────────────┘        │
│                                                             │
│  Purpose: All parsing, evaluation, command execution        │
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
│   ├── lib/                          # MoonBit core library
│   │   ├── ast/                      # AST type definitions
│   │   │   ├── types.mbt            # All AST node types (enum/struct)
│   │   │   └── moon.pkg.json
│   │   ├── lexer/                    # Tokenizer
│   │   │   ├── lexer.mbt            # Token types and lexer logic
│   │   │   ├── lexer_test.mbt       # Lexer unit tests
│   │   │   └── moon.pkg.json
│   │   ├── parser/                   # Recursive descent parser
│   │   │   ├── parser.mbt           # Main parser entry
│   │   │   ├── compound.mbt         # Compound command parsing
│   │   │   ├── expansion.mbt        # Expansion syntax parsing
│   │   │   ├── arithmetic.mbt       # Arithmetic expression parsing
│   │   │   ├── word.mbt             # Word/argument parsing
│   │   │   ├── parser_test.mbt
│   │   │   └── moon.pkg.json
│   │   ├── interpreter/              # AST evaluator
│   │   │   ├── interpreter.mbt      # Main execution loop
│   │   │   ├── expansion.mbt        # Runtime word expansion
│   │   │   ├── pipeline.mbt         # Pipe execution
│   │   │   ├── redirections.mbt     # I/O redirection handling
│   │   │   ├── control_flow.mbt     # if/for/while/case
│   │   │   ├── conditionals.mbt     # [[ ]] and [ ] evaluation
│   │   │   ├── arithmetic.mbt       # $((...)) evaluation
│   │   │   ├── functions.mbt        # Function def/invocation
│   │   │   ├── builtins/            # Shell builtins
│   │   │   │   ├── cd.mbt
│   │   │   │   ├── export.mbt
│   │   │   │   ├── declare.mbt
│   │   │   │   ├── set.mbt
│   │   │   │   ├── read.mbt
│   │   │   │   ├── echo.mbt
│   │   │   │   ├── printf.mbt
│   │   │   │   └── ...
│   │   │   └── moon.pkg.json
│   │   ├── commands/                 # External commands (80+)
│   │   │   ├── registry.mbt         # Command registry
│   │   │   ├── file_ops/            # cat, cp, ls, mkdir, etc.
│   │   │   ├── text/                # grep, sed, awk, sort, etc.
│   │   │   ├── data/                # jq, yq, xan
│   │   │   ├── compression/         # gzip, tar
│   │   │   ├── navigation/          # find, du, basename, etc.
│   │   │   ├── shell/               # date, seq, sleep, etc.
│   │   │   ├── network/             # curl
│   │   │   └── moon.pkg.json
│   │   ├── fs/                       # Virtual filesystem
│   │   │   ├── types.mbt            # IFileSystem trait
│   │   │   ├── inmemory.mbt         # InMemoryFs implementation
│   │   │   ├── overlay.mbt          # OverlayFs (via FFI)
│   │   │   ├── mountable.mbt        # MountableFs
│   │   │   ├── path.mbt             # Path normalization
│   │   │   ├── glob.mbt             # Glob pattern matching
│   │   │   └── moon.pkg.json
│   │   ├── regex/                    # Regex engine wrapper
│   │   │   ├── regex.mbt            # @moonbitlang/regexp integration
│   │   │   └── moon.pkg.json
│   │   ├── ffi/                      # JS interop definitions
│   │   │   ├── fs_callbacks.mbt     # Filesystem FFI
│   │   │   ├── network.mbt          # Network FFI
│   │   │   ├── async_bridge.mbt     # Async/Promise bridge
│   │   │   └── moon.pkg.json
│   │   └── moon.pkg.json
│   │
│   ├── wrapper/                      # TypeScript API layer
│   │   ├── index.ts                 # Main entry: class Bash
│   │   ├── sandbox.ts               # Sandbox API wrapper
│   │   ├── types.ts                 # TypeScript type definitions
│   │   └── bridge.ts               # JS<->MoonBit bridge setup
│   │
│   └── moon.mod.json                # MoonBit module config
│
├── tests/
│   ├── unit/                        # MoonBit unit tests
│   ├── comparison/                  # Bash behavior comparison tests
│   │   └── fixtures/               # Pre-recorded bash outputs
│   └── integration/                # Full-stack TS integration tests
│
├── docs/                            # This documentation
├── package.json                     # NPM package config
├── tsconfig.json                    # TypeScript config
└── tsup.config.ts                   # Bundling config
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
Pure JavaScript (moonbash-core.js)
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
