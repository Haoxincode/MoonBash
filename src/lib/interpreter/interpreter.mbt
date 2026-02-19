// moon_bash Interpreter
// Tree-walking interpreter that executes parsed AST.

// ============================================================================
// Execution Context
// ============================================================================

pub(all) struct ExecContext {
  // Environment
  mut env : Map[String, String]
  mut exported : Map[String, Bool]
  mut cwd : String

  // Functions
  mut functions : Map[String, @ast.FunctionDef]

  // Shell options
  mut options : @ast.ShellOptions

  // I/O
  mut stdin_buf : String
  mut stdout_buf : StringBuilder
  mut stderr_buf : StringBuilder

  // Control flow
  mut exit_code : Int
  mut should_exit : Bool
  mut loop_depth : Int
  mut break_count : Int
  mut continue_count : Int
  mut return_requested : Bool

  // Limits
  mut limits : @ast.ExecutionLimits
  mut command_count : Int
  mut call_depth : Int
  mut substitution_depth : Int
  mut glob_operations : Int

  // Filesystem
  fs : @fs.InMemoryFs
}

/// Create a new execution context.
pub fn ExecContext::new(
  fs : @fs.InMemoryFs,
  env~ : Map[String, String] = {},
  cwd~ : String = "/home/user",
  limits~ : @ast.ExecutionLimits = @ast.ExecutionLimits::default()
) -> ExecContext {
  let default_env : Map[String, String] = {}
  let default_exported : Map[String, Bool] = {}
  default_env["HOME"] = "/home/user"
  default_env["PATH"] = "/usr/bin:/bin"
  default_env["USER"] = "user"
  default_env["PWD"] = cwd
  default_env["IFS"] = " \t\n"
  default_env["SHELL"] = "/bin/bash"
  default_env["BASH_VERSION"] = "5.1.0(1)-release"
  for k, _v in default_env {
    default_exported[k] = true
  }
  // Merge user-provided env over defaults
  for k, v in env {
    default_env[k] = v
    default_exported[k] = true
  }
  {
    env: default_env,
    exported: default_exported,
    cwd,
    functions: {},
    options: @ast.ShellOptions::default(),
    stdin_buf: "",
    stdout_buf: StringBuilder::new(),
    stderr_buf: StringBuilder::new(),
    exit_code: 0,
    should_exit: false,
    loop_depth: 0,
    break_count: 0,
    continue_count: 0,
    return_requested: false,
    limits,
    command_count: 0,
    call_depth: 0,
    substitution_depth: 0,
    glob_operations: 0,
    fs,
  }
}

/// Parse and execute a script string.
pub fn ExecContext::execute(
  self : ExecContext,
  script : String
) -> @ast.ExecResult {
  // Reset I/O buffers
  self.stdout_buf = StringBuilder::new()
  self.stderr_buf = StringBuilder::new()
  self.should_exit = false
  self.return_requested = false
  self.substitution_depth = 0
  self.glob_operations = 0

  let parsed = try {
    @parser.parse(script)
  } catch {
    @ast.BashError(msg) =>
      return @ast.ExecResult::new(stderr="syntax error: " + msg + "\n", exit_code=2)
  }
  self.execute_script(parsed)
  @ast.ExecResult::new(
    stdout=self.stdout_buf.to_string(),
    stderr=self.stderr_buf.to_string(),
    exit_code=self.exit_code,
  )
}
