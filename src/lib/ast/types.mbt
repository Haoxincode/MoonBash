// MoonBash AST Type Definitions
// All types needed for lexing, parsing, and interpreting bash scripts.

// ============================================================================
// Token Types (Lexer output)
// ============================================================================

pub(all) enum Token {
  // Literals
  Word(String)
  Number(Int)
  AssignmentWord(String, String) // name, value

  // Operators
  Pipe // |
  PipeAnd // |&
  And // &&
  Or // ||
  Semi // ;
  Ampersand // &
  Newline

  // Redirections
  RedirectIn // <
  RedirectOut // >
  RedirectAppend // >>
  RedirectClobber // >|
  HereDoc // <<
  HereDocStrip // <<-
  HereString // <<<
  DupIn // <&
  DupOut // >&
  RedirectInOut // <>
  RedirectAndOut // &>
  RedirectAndAppend // &>>

  // Grouping
  LeftParen // (
  RightParen // )
  LeftBrace // {
  RightBrace // }
  DoubleBracketOpen // [[
  DoubleBracketClose // ]]

  // Reserved words
  If
  Then
  Elif
  Else
  Fi
  For
  While
  Until
  Do
  Done
  Case
  Esac
  In
  Function
  Select
  Bang // !
  Time

  // Special
  EOF
  FdNumber(Int) // File descriptor number before redirect
} derive(Show, Eq)

// ============================================================================
// AST Nodes
// ============================================================================

/// Top-level script: a sequence of statements.
pub(all) struct Script {
  statements : Array[Statement]
} derive(Show)

/// A statement is a pipeline combined with list operators.
pub(all) enum Statement {
  Pipeline(Pipeline)
  AndList(Pipeline, Statement) // cmd1 && cmd2
  OrList(Pipeline, Statement) // cmd1 || cmd2
  Background(Pipeline) // cmd &
  Sequence(Pipeline, Statement) // cmd1 ; cmd2
} derive(Show)

/// A pipeline connects commands via pipes.
pub(all) struct Pipeline {
  negated : Bool // ! prefix
  commands : Array[Command]
  pipe_stderr : Bool // |& instead of |
} derive(Show)

/// Command variants.
pub(all) enum Command {
  Simple(SimpleCommand)
  Compound(CompoundCommand, Array[Redirection])
  FunctionDef(FunctionDef)
} derive(Show)

/// A simple command with optional assignments, words, and redirections.
pub(all) struct SimpleCommand {
  assignments : Array[Assignment]
  words : Array[Word]
  redirections : Array[Redirection]
} derive(Show)

/// Compound command variants.
pub(all) enum CompoundCommand {
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
} derive(Show)

/// if/elif/else/fi clause.
pub(all) struct IfClause {
  condition : Script
  then_branch : Script
  elif_branches : Array[(Script, Script)]
  else_branch : Script?
} derive(Show)

/// for var in words; do body; done
pub(all) struct ForClause {
  var_name : String
  words : Array[Word]? // None = "$@"
  body : Script
} derive(Show)

/// C-style for: for (( init; cond; update )); do body; done
pub(all) struct CStyleForClause {
  init : ArithExpr
  condition : ArithExpr
  update : ArithExpr
  body : Script
} derive(Show)

/// while condition; do body; done
pub(all) struct WhileClause {
  condition : Script
  body : Script
} derive(Show)

/// until condition; do body; done
pub(all) struct UntilClause {
  condition : Script
  body : Script
} derive(Show)

/// case word in pattern) body ;; esac
pub(all) struct CaseClause {
  word : Word
  items : Array[CaseItem]
} derive(Show)

/// A single case item: pattern) body terminator
pub(all) struct CaseItem {
  patterns : Array[Word]
  body : Script
  terminator : CaseTerminator
} derive(Show)

/// Case item terminators.
pub(all) enum CaseTerminator {
  Break // ;;
  Fallthrough // ;&
  Continue // ;;&
} derive(Show, Eq)

/// Function definition.
pub(all) struct FunctionDef {
  name : String
  body : CompoundCommand
  redirections : Array[Redirection]
} derive(Show)

// ============================================================================
// Word and Expansion Types
// ============================================================================

/// A word is composed of parts that may need expansion.
pub(all) struct Word {
  parts : Array[WordPart]
} derive(Show)

/// Individual parts of a word.
pub(all) enum WordPart {
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
} derive(Show)

/// Parameter expansion variants.
pub(all) enum ParamExpansion {
  Simple(String) // $VAR
  Default(String, Word, Bool) // ${VAR:-word} / ${VAR-word}
  Assign(String, Word, Bool) // ${VAR:=word} / ${VAR=word}
  Error(String, Word?, Bool) // ${VAR:?word} / ${VAR?word}
  Alternative(String, Word, Bool) // ${VAR:+word} / ${VAR+word}
  Length(String) // ${#VAR}
  Substring(String, ArithExpr, ArithExpr?) // ${VAR:offset:length}
  PrefixRemove(String, Word, Bool) // ${VAR#pat} / ${VAR##pat}
  SuffixRemove(String, Word, Bool) // ${VAR%pat} / ${VAR%%pat}
  Replace(String, Word, Word?, ReplaceMode) // ${VAR/pat/str}
  Uppercase(String, Word?, Bool) // ${VAR^pat} / ${VAR^^pat}
  Lowercase(String, Word?, Bool) // ${VAR,pat} / ${VAR,,pat}
  Indirection(String) // ${!VAR}
} derive(Show)

/// Replace mode for ${VAR/pat/str} variants.
pub(all) enum ReplaceMode {
  First // ${VAR/pat/str}
  All // ${VAR//pat/str}
  Prefix // ${VAR/#pat/str}
  Suffix // ${VAR/%pat/str}
} derive(Show, Eq)

// ============================================================================
// Redirection Types
// ============================================================================

/// A redirection specification.
pub(all) struct Redirection {
  fd : Int? // File descriptor (None = default)
  fd_var : String? // {varname} for fd variable
  op : RedirectOp
  target : Word
} derive(Show)

/// Redirection operator variants.
pub(all) enum RedirectOp {
  Input // <
  Output // >
  Append // >>
  Clobber // >|
  InputOutput // <>
  HereDoc(Bool) // << (strip_tabs: Bool)
  HereString // <<<
  DupInput // <&
  DupOutput // >&
  AndOutput // &>
  AndAppend // &>>
} derive(Show, Eq)

// ============================================================================
// Assignment
// ============================================================================

/// A variable assignment: name=value or name+=value
pub(all) struct Assignment {
  name : String
  value : Word?
  append : Bool // += vs =
} derive(Show)

// ============================================================================
// Arithmetic Expressions (placeholder, expanded later)
// ============================================================================

pub(all) enum ArithExpr {
  Num(Int)
  Var(String)
  BinOp(ArithBinOp, ArithExpr, ArithExpr)
  UnaryOp(ArithUnaryOp, ArithExpr)
  Assign(String, ArithExpr)
  Ternary(ArithExpr, ArithExpr, ArithExpr)
  Raw(String)
} derive(Show)

pub(all) enum ArithBinOp {
  Add
  Sub
  Mul
  Div
  Mod
  Pow
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  BitwiseAnd
  BitwiseOr
  BitwiseXor
  ShiftLeft
  ShiftRight
  LogicalAnd
  LogicalOr
} derive(Show, Eq)

pub(all) enum ArithUnaryOp {
  Negate
  BitwiseNot
  LogicalNot
  PreIncr
  PreDecr
  PostIncr
  PostDecr
} derive(Show, Eq)

// ============================================================================
// Conditional Expressions (placeholder, expanded later)
// ============================================================================

pub(all) enum CondExpr {
  UnaryTest(String, Word) // -f, -d, -e, -z, -n, etc.
  BinaryTest(Word, String, Word) // =, !=, -eq, -gt, etc.
  And(CondExpr, CondExpr) // &&
  Or(CondExpr, CondExpr) // ||
  Not(CondExpr) // !
  Regex(Word, Word) // =~
} derive(Show)

// ============================================================================
// Glob Pattern (placeholder)
// ============================================================================

pub(all) struct GlobPattern {
  pattern : String
} derive(Show)

// ============================================================================
// Execution Result
// ============================================================================

pub(all) struct ExecResult {
  stdout : String
  stderr : String
  exit_code : Int
} derive(Show)

/// Create a successful result with stdout output.
pub fn ExecResult::ok(stdout : String) -> ExecResult {
  { stdout, stderr: "", exit_code: 0 }
}

/// Create an error result with stderr output.
pub fn ExecResult::err(stderr : String) -> ExecResult {
  { stdout: "", stderr, exit_code: 1 }
}

/// Create a result with named parameters.
pub fn ExecResult::new(
  stdout~ : String = "",
  stderr~ : String = "",
  exit_code~ : Int = 0
) -> ExecResult {
  { stdout, stderr, exit_code }
}

// ============================================================================
// Error Type
// ============================================================================

pub(all) suberror BashError {
  BashError(String)
}

// ============================================================================
// Execution Limits
// ============================================================================

pub(all) struct ExecutionLimits {
  max_call_depth : Int
  max_command_count : Int
  max_loop_iterations : Int
  max_string_length : Int
  max_array_elements : Int
  max_heredoc_size : Int
  max_substitution_depth : Int
  max_glob_operations : Int
  max_awk_iterations : Int
  max_sed_iterations : Int
  max_jq_iterations : Int
} derive(Show)

pub fn ExecutionLimits::default() -> ExecutionLimits {
  {
    max_call_depth: 100,
    max_command_count: 10000,
    max_loop_iterations: 10000,
    max_string_length: 10 * 1024 * 1024, // 10 MB
    max_array_elements: 100000,
    max_heredoc_size: 10 * 1024 * 1024, // 10 MB
    max_substitution_depth: 50,
    max_glob_operations: 100000,
    max_awk_iterations: 10000,
    max_sed_iterations: 10000,
    max_jq_iterations: 10000,
  }
}

// ============================================================================
// Shell Options
// ============================================================================

pub(all) struct ShellOptions {
  mut errexit : Bool // set -e
  mut nounset : Bool // set -u
  mut pipefail : Bool // set -o pipefail
  mut noclobber : Bool // set -C
  mut xtrace : Bool // set -x
  mut noglob : Bool // set -f
  mut allexport : Bool // set -a
} derive(Show)

pub fn ShellOptions::default() -> ShellOptions {
  {
    errexit: false,
    nounset: false,
    pipefail: false,
    noclobber: false,
    xtrace: false,
    noglob: false,
    allexport: false,
  }
}
