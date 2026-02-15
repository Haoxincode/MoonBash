// MoonBash Interpreter
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
  limits : @ast.ExecutionLimits
  mut command_count : Int
  mut call_depth : Int

  // Filesystem
  fs : @fs.InMemoryFs
}

/// Create a new execution context.
pub fn ExecContext::new(
  fs : @fs.InMemoryFs,
  env~ : Map[String, String] = {},
  cwd~ : String = "/home/user"
) -> ExecContext {
  let default_env : Map[String, String] = {}
  default_env["HOME"] = "/home/user"
  default_env["PATH"] = "/usr/bin:/bin"
  default_env["USER"] = "user"
  default_env["PWD"] = cwd
  default_env["IFS"] = " \t\n"
  default_env["SHELL"] = "/bin/bash"
  // Merge user-provided env over defaults
  for k, v in env {
    default_env[k] = v
  }
  {
    env: default_env,
    exported: {},
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
    limits: @ast.ExecutionLimits::default(),
    command_count: 0,
    call_depth: 0,
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

  let parsed = try {
    @parser.parse(script)
  } catch {
    @ast.BashError(msg) =>
      return @ast.ExecResult::new(stderr=msg + "\n", exit_code=2)
  }
  self.execute_script(parsed)
  @ast.ExecResult::new(
    stdout=self.stdout_buf.to_string(),
    stderr=self.stderr_buf.to_string(),
    exit_code=self.exit_code,
  )
}

// ============================================================================
// Script Execution
// ============================================================================

fn ExecContext::execute_script(self : ExecContext, script : @ast.Script) -> Unit {
  for stmt in script.statements {
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 || self.continue_count > 0 {
      break
    }
    self.execute_statement(stmt)
  }
}

// ============================================================================
// Statement Execution
// ============================================================================

fn ExecContext::execute_statement(
  self : ExecContext,
  stmt : @ast.Statement
) -> Unit {
  match stmt {
    @ast.Statement::Pipeline(pipeline) => self.execute_pipeline(pipeline)
    @ast.Statement::AndList(pipeline, next) => {
      self.execute_pipeline(pipeline)
      if self.exit_code == 0 {
        self.execute_statement(next)
      }
    }
    @ast.Statement::OrList(pipeline, next) => {
      self.execute_pipeline(pipeline)
      if self.exit_code != 0 {
        self.execute_statement(next)
      }
    }
    @ast.Statement::Sequence(pipeline, next) => {
      self.execute_pipeline(pipeline)
      if not(self.should_exit) && not(self.return_requested) {
        self.execute_statement(next)
      }
    }
    @ast.Statement::Background(pipeline) => {
      // In sandbox, background just executes synchronously
      self.execute_pipeline(pipeline)
    }
  }
}

// ============================================================================
// Pipeline Execution
// ============================================================================

fn ExecContext::execute_pipeline(
  self : ExecContext,
  pipeline : @ast.Pipeline
) -> Unit {
  let commands = pipeline.commands
  if commands.length() == 0 {
    return
  }

  if commands.length() == 1 {
    // Single command, no piping needed
    self.execute_command(commands[0])
  } else {
    // Multi-command pipeline: chain stdout -> stdin
    let saved_stdin = self.stdin_buf
    let saved_stdout = self.stdout_buf

    let mut pipe_input = self.stdin_buf
    for i = 0; i < commands.length(); i = i + 1 {
      self.stdin_buf = pipe_input
      self.stdout_buf = StringBuilder::new()
      self.execute_command(commands[i])
      pipe_input = self.stdout_buf.to_string()
    }

    // Write final command output to the original stdout
    saved_stdout.write_string(pipe_input)
    self.stdout_buf = saved_stdout
    self.stdin_buf = saved_stdin
  }

  // Handle negation
  if pipeline.negated {
    self.exit_code = if self.exit_code == 0 { 1 } else { 0 }
  }
}

// ============================================================================
// Command Execution
// ============================================================================

fn ExecContext::execute_command(self : ExecContext, cmd : @ast.Command) -> Unit {
  // Check command count limit
  self.command_count += 1
  if self.command_count > self.limits.max_command_count {
    self.stderr_buf.write_string("moonbash: command limit exceeded\n")
    self.exit_code = 1
    self.should_exit = true
    return
  }

  match cmd {
    @ast.Command::Simple(simple) => self.execute_simple(simple)
    @ast.Command::Compound(compound, redirs) => {
      // Save and apply redirections
      let saved_stdout = self.stdout_buf
      let saved_stderr = self.stderr_buf
      let mut redirected_file : String? = None
      let mut redirect_append = false
      self.apply_redirections(redirs, saved_stdout, saved_stderr)
      // Check if we redirected to a file
      for redir in redirs {
        match redir.op {
          @ast.RedirectOp::Output => {
            let target = self.expand_word_to_string(redir.target)
            if target != "/dev/null" && target != "/dev/stdout" && target != "/dev/stderr" {
              redirected_file = Some(target)
              redirect_append = false
            }
          }
          @ast.RedirectOp::Append => {
            let target = self.expand_word_to_string(redir.target)
            if target != "/dev/null" && target != "/dev/stdout" && target != "/dev/stderr" {
              redirected_file = Some(target)
              redirect_append = true
            }
          }
          _ => ()
        }
      }
      self.execute_compound(compound)
      // Flush redirected output to file if needed
      match redirected_file {
        Some(path) => {
          let output = self.stdout_buf.to_string()
          let resolved = try {
            @fs.resolve_path(self.cwd, path)
          } catch {
            _ => path
          }
          try {
            if redirect_append {
              self.fs.append_file(resolved, output)
            } else {
              self.fs.write_file(resolved, output)
            }
          } catch {
            @fs.FsError(msg) =>
              self.stderr_buf.write_string("moonbash: \{msg}\n")
          }
          self.stdout_buf = saved_stdout
        }
        None => ()
      }
    }
    @ast.Command::FunctionDef(fndef) =>
      self.functions[fndef.name] = fndef
  }
}

// ============================================================================
// Simple Command Execution
// ============================================================================

fn ExecContext::execute_simple(
  self : ExecContext,
  cmd : @ast.SimpleCommand
) -> Unit {
  // Handle assignments
  let has_words = cmd.words.length() > 0

  // Process variable assignments
  if cmd.assignments.length() > 0 {
    for assign in cmd.assignments {
      let value = match assign.value {
        Some(word) => self.expand_word_to_string(word)
        None => ""
      }
      if assign.append {
        let existing = self.env.get(assign.name).unwrap_or("")
        self.env[assign.name] = existing + value
      } else {
        self.env[assign.name] = value
      }
    }
    // If no words follow, we're done (assignment-only command)
    if not(has_words) {
      self.exit_code = 0
      return
    }
  }

  // Expand all words
  let expanded : Array[String] = []
  for word in cmd.words {
    let parts = self.expand_word(word)
    for part in parts {
      expanded.push(part)
    }
  }

  if expanded.length() == 0 {
    self.exit_code = 0
    return
  }

  let cmd_name = expanded[0]
  let args : Array[String] = []
  for i = 1; i < expanded.length(); i = i + 1 {
    args.push(expanded[i])
  }

  // Apply redirections
  let saved_stdout = self.stdout_buf
  let saved_stderr = self.stderr_buf
  let saved_stdin = self.stdin_buf
  let mut redirected_file : String? = None
  let mut redirect_append = false
  let mut null_output = false
  let mut input_from_file = false

  for redir in cmd.redirections {
    match redir.op {
      @ast.RedirectOp::Output => {
        let target = self.expand_word_to_string(redir.target)
        if target == "/dev/null" {
          null_output = true
          self.stdout_buf = StringBuilder::new()
        } else if target == "/dev/stderr" {
          // stdout goes to stderr - noop in sandbox
        } else {
          redirected_file = Some(target)
          redirect_append = false
          self.stdout_buf = StringBuilder::new()
        }
      }
      @ast.RedirectOp::Append => {
        let target = self.expand_word_to_string(redir.target)
        if target == "/dev/null" {
          null_output = true
          self.stdout_buf = StringBuilder::new()
        } else {
          redirected_file = Some(target)
          redirect_append = true
          self.stdout_buf = StringBuilder::new()
        }
      }
      @ast.RedirectOp::Input => {
        let target = self.expand_word_to_string(redir.target)
        let resolved = try {
          @fs.resolve_path(self.cwd, target)
        } catch {
          _ => target
        }
        let content = try {
          self.fs.read_file(resolved)
        } catch {
          @fs.FsError(msg) => {
            self.stderr_buf.write_string("moonbash: \{msg}\n")
            self.exit_code = 1
            return
          }
        }
        self.stdin_buf = content
        input_from_file = true
      }
      @ast.RedirectOp::HereString => {
        let content = self.expand_word_to_string(redir.target)
        self.stdin_buf = content + "\n"
        input_from_file = true
      }
      @ast.RedirectOp::AndOutput => {
        let target = self.expand_word_to_string(redir.target)
        if target == "/dev/null" {
          null_output = true
          self.stdout_buf = StringBuilder::new()
        }
      }
      _ => ()
    }
  }

  // Execute command
  self.run_command(cmd_name, args)

  // Handle redirections output
  match redirected_file {
    Some(path) => {
      let output = self.stdout_buf.to_string()
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        if redirect_append {
          self.fs.append_file(resolved, output)
        } else {
          self.fs.write_file(resolved, output)
        }
      } catch {
        @fs.FsError(msg) =>
          self.stderr_buf.write_string("moonbash: \{msg}\n")
      }
      self.stdout_buf = saved_stdout
    }
    None => {
      if null_output {
        self.stdout_buf = saved_stdout
      }
    }
  }

  if input_from_file {
    self.stdin_buf = saved_stdin
  }
}

// ============================================================================
// Command Dispatch
// ============================================================================

fn ExecContext::run_command(
  self : ExecContext,
  name : String,
  args : Array[String]
) -> Unit {
  // 1. Check functions
  match self.functions.get(name) {
    Some(fndef) => {
      self.call_depth += 1
      if self.call_depth > self.limits.max_call_depth {
        self.stderr_buf.write_string(
          "moonbash: maximum call depth exceeded\n",
        )
        self.exit_code = 1
        self.call_depth -= 1
        return
      }
      // Save positional params
      let saved_args = self.env.get("@").unwrap_or("")
      self.env["@"] = args.iter().fold(
        init="",
        fn(acc, a) { if acc.length() == 0 { a } else { acc + " " + a } },
      )
      self.env["#"] = args.length().to_string()
      for i = 0; i < args.length(); i = i + 1 {
        self.env[(i + 1).to_string()] = args[i]
      }
      // Execute function body
      match fndef.body {
        @ast.CompoundCommand::Group(script) => self.execute_script(script)
        other => self.execute_compound(other)
      }
      self.return_requested = false
      // Restore
      self.env["@"] = saved_args
      self.call_depth -= 1
      return
    }
    None => ()
  }

  // 2. Handle cd specially (needs to modify cwd)
  if name == "cd" {
    let target = if args.length() == 0 {
      self.env.get("HOME").unwrap_or("/home/user")
    } else if args[0] == "-" {
      self.env.get("OLDPWD").unwrap_or(self.cwd)
    } else {
      args[0]
    }
    let resolved = try {
      @fs.resolve_path(self.cwd, target)
    } catch {
      _ => {
        self.stderr_buf.write_string("cd: no such file or directory: \{target}\n")
        self.exit_code = 1
        return
      }
    }
    match self.fs.entries.get(resolved) {
      Some(@fs.FsEntry::Directory(_)) => {
        let old_pwd = self.cwd
        self.cwd = resolved
        self.env["PWD"] = resolved
        self.env["OLDPWD"] = old_pwd
        self.exit_code = 0
      }
      Some(_) => {
        self.stderr_buf.write_string("cd: not a directory: \{target}\n")
        self.exit_code = 1
      }
      None => {
        self.stderr_buf.write_string("cd: no such file or directory: \{target}\n")
        self.exit_code = 1
      }
    }
    return
  }

  // 3. Check builtins
  if self.run_builtin(name, args) {
    return
  }

  // 4. Check command registry
  match @commands.find_command(name) {
    Some(cmd_fn) => {
      let ctx : @commands.CommandContext = {
        args,
        stdin_content: self.stdin_buf,
        cwd: self.cwd,
        env: self.env,
        fs: self.fs,
      }
      let result = cmd_fn(ctx)
      self.stdout_buf.write_string(result.stdout)
      self.stderr_buf.write_string(result.stderr)
      self.exit_code = result.exit_code
      return
    }
    None => ()
  }

  // 5. Command not found
  self.stderr_buf.write_string("moonbash: \{name}: command not found\n")
  self.exit_code = 127
}

// ============================================================================
// Builtins
// ============================================================================

fn ExecContext::run_builtin(
  self : ExecContext,
  name : String,
  args : Array[String]
) -> Bool {
  match name {
    "export" => {
      self.builtin_export(args)
      true
    }
    "unset" => {
      self.builtin_unset(args)
      true
    }
    "set" => {
      self.builtin_set(args)
      true
    }
    "shift" => {
      self.builtin_shift(args)
      true
    }
    "exit" => {
      self.builtin_exit(args)
      true
    }
    "return" => {
      self.builtin_return(args)
      true
    }
    "break" => {
      self.builtin_break(args)
      true
    }
    "continue" => {
      self.builtin_continue(args)
      true
    }
    "read" => {
      self.builtin_read(args)
      true
    }
    "test" | "[" => {
      self.builtin_test(args)
      true
    }
    "printf" => {
      self.builtin_printf(args)
      true
    }
    "eval" => {
      self.builtin_eval(args)
      true
    }
    "source" | "." => {
      self.builtin_source(args)
      true
    }
    "local" => {
      self.builtin_local(args)
      true
    }
    "declare" | "typeset" => {
      self.builtin_declare(args)
      true
    }
    ":" => {
      self.exit_code = 0
      true
    }
    "type" => {
      self.builtin_type(args)
      true
    }
    "command" => {
      self.builtin_command(args)
      true
    }
    "basename" => {
      self.builtin_basename(args)
      true
    }
    "dirname" => {
      self.builtin_dirname(args)
      true
    }
    "seq" => {
      self.builtin_seq(args)
      true
    }
    "rev" => {
      self.builtin_rev(args)
      true
    }
    "tr" => {
      self.builtin_tr(args)
      true
    }
    "sort" => {
      self.builtin_sort(args)
      true
    }
    "uniq" => {
      self.builtin_uniq(args)
      true
    }
    "cut" => {
      self.builtin_cut(args)
      true
    }
    "tee" => {
      self.builtin_tee(args)
      true
    }
    "grep" => {
      self.builtin_grep(args)
      true
    }
    "xargs" => {
      self.builtin_xargs(args)
      true
    }
    "date" => {
      self.builtin_date(args)
      true
    }
    "env" | "printenv" => {
      self.builtin_env(args)
      true
    }
    "which" => {
      self.builtin_which(args)
      true
    }
    _ => false
  }
}

// ============================================================================
// Builtin Implementations
// ============================================================================

fn ExecContext::builtin_export(self : ExecContext, args : Array[String]) -> Unit {
  if args.length() == 0 {
    // List exported vars
    for k, _v in self.exported {
      let value = self.env.get(k).unwrap_or("")
      self.stdout_buf.write_string("declare -x \{k}=\"\{value}\"\n")
    }
    self.exit_code = 0
    return
  }
  for arg in args {
    // Check for name=value
    let mut eq_pos = -1
    for i = 0; i < arg.length(); i = i + 1 {
      if arg[i] == '=' {
        eq_pos = i
        break
      }
    }
    if eq_pos > 0 {
      let name = arg.substring(start=0, end=eq_pos)
      let value = arg.substring(start=eq_pos + 1)
      self.env[name] = value
      self.exported[name] = true
    } else {
      self.exported[arg] = true
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_unset(self : ExecContext, args : Array[String]) -> Unit {
  for arg in args {
    self.env.remove(arg)
    self.exported.remove(arg)
  }
  self.exit_code = 0
}

fn ExecContext::builtin_set(self : ExecContext, args : Array[String]) -> Unit {
  if args.length() == 0 {
    // Print all variables
    for k, v in self.env {
      self.stdout_buf.write_string("\{k}=\{v}\n")
    }
    self.exit_code = 0
    return
  }
  for arg in args {
    if arg.length() >= 2 && arg[0] == '-' {
      let ch = arg.substring(start=1, end=2)
      match ch {
        "e" => self.options.errexit = true
        "u" => self.options.nounset = true
        "f" => self.options.noglob = true
        "x" => self.options.xtrace = true
        "C" => self.options.noclobber = true
        "a" => self.options.allexport = true
        "o" => () // set -o pipefail etc. - check next arg
        _ => ()
      }
    } else if arg.length() >= 2 && arg[0] == '+' {
      let ch = arg.substring(start=1, end=2)
      match ch {
        "e" => self.options.errexit = false
        "u" => self.options.nounset = false
        "f" => self.options.noglob = false
        "x" => self.options.xtrace = false
        "C" => self.options.noclobber = false
        "a" => self.options.allexport = false
        _ => ()
      }
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_shift(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let n = if args.length() > 0 { parse_int_str(args[0]) } else { 1 }
  let count = match self.env.get("#") {
    Some(s) => parse_int_str(s)
    None => 0
  }
  if n > count {
    self.stderr_buf.write_string("moonbash: shift: count exceeds positional parameters\n")
    self.exit_code = 1
    return
  }
  for i = 1; i <= count - n; i = i + 1 {
    let src_idx = i + n
    match self.env.get(src_idx.to_string()) {
      Some(v) => self.env[i.to_string()] = v
      None => ()
    }
  }
  for i = count - n + 1; i <= count; i = i + 1 {
    self.env.remove(i.to_string())
  }
  self.env["#"] = (count - n).to_string()
  self.exit_code = 0
}

fn ExecContext::builtin_exit(self : ExecContext, args : Array[String]) -> Unit {
  self.exit_code = if args.length() > 0 {
    parse_int_str(args[0])
  } else {
    self.exit_code
  }
  self.should_exit = true
}

fn ExecContext::builtin_return(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  self.exit_code = if args.length() > 0 {
    parse_int_str(args[0])
  } else {
    self.exit_code
  }
  self.return_requested = true
}

fn ExecContext::builtin_break(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let n = if args.length() > 0 { parse_int_str(args[0]) } else { 1 }
  if self.loop_depth > 0 {
    self.break_count = n
  }
  self.exit_code = 0
}

fn ExecContext::builtin_continue(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let n = if args.length() > 0 { parse_int_str(args[0]) } else { 1 }
  if self.loop_depth > 0 {
    self.continue_count = n
  }
  self.exit_code = 0
}

fn ExecContext::builtin_read(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let input = self.stdin_buf
  // Find first line
  let mut line_end = input.length()
  for i = 0; i < input.length(); i = i + 1 {
    if input[i] == '\n' {
      line_end = i
      break
    }
  }
  let line = input.substring(start=0, end=line_end)

  // Parse flags
  let var_names : Array[String] = []
  let mut prompt = ""
  let mut i = 0
  while i < args.length() {
    if args[i] == "-p" && i + 1 < args.length() {
      prompt = args[i + 1]
      i += 2
    } else if args[i] == "-r" {
      i += 1
    } else {
      var_names.push(args[i])
      i += 1
    }
  }
  if prompt.length() > 0 {
    self.stderr_buf.write_string(prompt)
  }

  if var_names.length() == 0 {
    var_names.push("REPLY")
  }

  // Split line by IFS and assign to variables
  let words = split_by_whitespace(line)
  for j = 0; j < var_names.length(); j = j + 1 {
    if j < var_names.length() - 1 {
      // Not the last variable - assign one word
      let value = if j < words.length() { words[j] } else { "" }
      self.env[var_names[j]] = value
    } else {
      // Last variable - assign rest of line
      if j < words.length() {
        let buf = StringBuilder::new()
        for k = j; k < words.length(); k = k + 1 {
          if k > j {
            buf.write_string(" ")
          }
          buf.write_string(words[k])
        }
        self.env[var_names[j]] = buf.to_string()
      } else {
        self.env[var_names[j]] = ""
      }
    }
  }

  // Consume the line from stdin
  if line_end < input.length() {
    self.stdin_buf = input.substring(start=line_end + 1)
  } else {
    self.stdin_buf = ""
  }

  self.exit_code = if input.length() == 0 { 1 } else { 0 }
}

fn ExecContext::builtin_test(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // Remove trailing ] if command was [
  let test_args = if args.length() > 0 && args[args.length() - 1] == "]" {
    let a : Array[String] = []
    for i = 0; i < args.length() - 1; i = i + 1 {
      a.push(args[i])
    }
    a
  } else {
    args
  }

  self.exit_code = if evaluate_test(test_args, self) { 0 } else { 1 }
}

fn ExecContext::builtin_printf(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("printf: usage: printf format [arguments]\n")
    self.exit_code = 1
    return
  }
  let format = args[0]
  let fmt_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    fmt_args.push(args[i])
  }
  let result = format_printf(format, fmt_args)
  self.stdout_buf.write_string(result)
  self.exit_code = 0
}

fn ExecContext::builtin_eval(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 0
    return
  }
  let script = args.iter().fold(
    init="",
    fn(acc, a) { if acc.length() == 0 { a } else { acc + " " + a } },
  )
  let parsed = try {
    @parser.parse(script)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moonbash: eval: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
}

fn ExecContext::builtin_source(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("moonbash: source: filename argument required\n")
    self.exit_code = 2
    return
  }
  let path = try {
    @fs.resolve_path(self.cwd, args[0])
  } catch {
    _ => args[0]
  }
  let content = try {
    self.fs.read_file(path)
  } catch {
    @fs.FsError(msg) => {
      self.stderr_buf.write_string("moonbash: source: \{msg}\n")
      self.exit_code = 1
      return
    }
  }
  let parsed = try {
    @parser.parse(content)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moonbash: source: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
}

fn ExecContext::builtin_local(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // In our sandbox, local behaves like regular assignment
  for arg in args {
    let mut eq_pos = -1
    for i = 0; i < arg.length(); i = i + 1 {
      if arg[i] == '=' {
        eq_pos = i
        break
      }
    }
    if eq_pos > 0 {
      let name = arg.substring(start=0, end=eq_pos)
      let value = arg.substring(start=eq_pos + 1)
      self.env[name] = value
    } else {
      if not(self.env.contains(arg)) {
        self.env[arg] = ""
      }
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_declare(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // Simplified: treat like local/assignment
  let filtered : Array[String] = []
  for arg in args {
    // Skip flags like -r, -i, -a, etc.
    if arg.length() > 0 && arg[0] == '-' {
      continue
    }
    filtered.push(arg)
  }
  self.builtin_local(filtered)
}

fn ExecContext::builtin_type(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  for arg in args {
    if self.functions.contains(arg) {
      self.stdout_buf.write_string("\{arg} is a function\n")
    } else if is_shell_builtin(arg) {
      self.stdout_buf.write_string("\{arg} is a shell builtin\n")
    } else {
      match @commands.find_command(arg) {
        Some(_) => self.stdout_buf.write_string("\{arg} is /usr/bin/\{arg}\n")
        None =>
          self.stderr_buf.write_string(
            "moonbash: type: \{arg}: not found\n",
          )
      }
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_command(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 0
    return
  }
  // Skip -v flag
  let mut start = 0
  if args[0] == "-v" {
    start = 1
  }
  if start >= args.length() {
    self.exit_code = 0
    return
  }
  let cmd_name = args[start]
  let cmd_args : Array[String] = []
  for i = start + 1; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }
  // Execute without function lookup
  if self.run_builtin(cmd_name, cmd_args) {
    return
  }
  match @commands.find_command(cmd_name) {
    Some(cmd_fn) => {
      let ctx : @commands.CommandContext = {
        args: cmd_args,
        stdin_content: self.stdin_buf,
        cwd: self.cwd,
        env: self.env,
        fs: self.fs,
      }
      let result = cmd_fn(ctx)
      self.stdout_buf.write_string(result.stdout)
      self.stderr_buf.write_string(result.stderr)
      self.exit_code = result.exit_code
    }
    None => {
      self.stderr_buf.write_string("moonbash: \{cmd_name}: command not found\n")
      self.exit_code = 127
    }
  }
}

fn ExecContext::builtin_basename(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("basename: missing operand\n")
    self.exit_code = 1
    return
  }
  let path = args[0]
  let mut name = @fs.basename(path)
  // Remove suffix if provided
  if args.length() > 1 {
    let suffix = args[1]
    if name.length() > suffix.length() && name.has_suffix(suffix) {
      name = name.substring(start=0, end=name.length() - suffix.length())
    }
  }
  self.stdout_buf.write_string(name + "\n")
  self.exit_code = 0
}

fn ExecContext::builtin_dirname(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("dirname: missing operand\n")
    self.exit_code = 1
    return
  }
  let path = args[0]
  let parent = @fs.parent_path(path)
  // dirname returns "." for paths without a slash
  let result = if parent == "/" && not(path.has_prefix("/")) {
    "."
  } else if parent == path {
    "."
  } else {
    parent
  }
  self.stdout_buf.write_string(result + "\n")
  self.exit_code = 0
}

fn ExecContext::builtin_seq(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("seq: missing operand\n")
    self.exit_code = 1
    return
  }
  let mut first = 1
  let mut incr = 1
  let mut last = 1
  if args.length() == 1 {
    last = parse_int_str(args[0])
  } else if args.length() == 2 {
    first = parse_int_str(args[0])
    last = parse_int_str(args[1])
  } else {
    first = parse_int_str(args[0])
    incr = parse_int_str(args[1])
    last = parse_int_str(args[2])
  }
  if incr == 0 {
    self.stderr_buf.write_string("seq: zero increment\n")
    self.exit_code = 1
    return
  }
  let mut i = first
  let mut count = 0
  while (incr > 0 && i <= last) || (incr < 0 && i >= last) {
    self.stdout_buf.write_string(i.to_string() + "\n")
    i += incr
    count += 1
    if count > self.limits.max_loop_iterations {
      break
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_rev(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let input = if args.length() > 0 {
    // Read from file
    let path = try {
      @fs.resolve_path(self.cwd, args[0])
    } catch {
      _ => args[0]
    }
    try {
      self.fs.read_file(path)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("rev: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
  } else {
    self.stdin_buf
  }
  let lines = split_lines(input)
  for line in lines {
    let reversed = reverse_string(line)
    self.stdout_buf.write_string(reversed + "\n")
  }
  self.exit_code = 0
}

fn ExecContext::builtin_tr(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() < 2 {
    // Check for -d flag
    if args.length() == 1 {
      self.stderr_buf.write_string("tr: missing operand\n")
      self.exit_code = 1
      return
    }
    self.stderr_buf.write_string("tr: missing operand\n")
    self.exit_code = 1
    return
  }
  let input = self.stdin_buf
  let mut delete_mode = false
  let mut set1_idx = 0
  let mut set2_idx = 1

  if args[0] == "-d" {
    delete_mode = true
    set1_idx = 1
    set2_idx = 2
  }

  let set1 = expand_tr_set(args[set1_idx])

  if delete_mode {
    let buf = StringBuilder::new()
    for i = 0; i < input.length(); i = i + 1 {
      let ch = input[i].to_int().unsafe_to_char()
      if not(tr_set_contains(set1, ch)) {
        buf.write_char(ch)
      }
    }
    self.stdout_buf.write_string(buf.to_string())
  } else {
    if set2_idx >= args.length() {
      self.stderr_buf.write_string("tr: missing operand after set1\n")
      self.exit_code = 1
      return
    }
    let set2 = expand_tr_set(args[set2_idx])
    let buf = StringBuilder::new()
    for i = 0; i < input.length(); i = i + 1 {
      let ch = input[i].to_int().unsafe_to_char()
      let replacement = tr_translate(set1, set2, ch)
      buf.write_char(replacement)
    }
    self.stdout_buf.write_string(buf.to_string())
  }
  self.exit_code = 0
}

fn ExecContext::builtin_sort(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut reverse = false
  let mut numeric = false
  let mut unique = false
  let mut input_file : String? = None

  for arg in args {
    match arg {
      "-r" => reverse = true
      "-n" => numeric = true
      "-u" => unique = true
      "-rn" | "-nr" => { reverse = true; numeric = true }
      _ => input_file = Some(arg)
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("sort: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)

  // Simple bubble sort
  let sorted = lines
  for i = 0; i < sorted.length(); i = i + 1 {
    for j = 0; j < sorted.length() - i - 1; j = j + 1 {
      let should_swap = if numeric {
        let a = parse_int_str(sorted[j])
        let b = parse_int_str(sorted[j + 1])
        if reverse { a < b } else { a > b }
      } else {
        if reverse { sorted[j] < sorted[j + 1] } else { sorted[j] > sorted[j + 1] }
      }
      if should_swap {
        let tmp = sorted[j]
        sorted[j] = sorted[j + 1]
        sorted[j + 1] = tmp
      }
    }
  }

  // Handle unique
  let mut prev = ""
  for i = 0; i < sorted.length(); i = i + 1 {
    if unique && i > 0 && sorted[i] == prev {
      continue
    }
    self.stdout_buf.write_string(sorted[i] + "\n")
    prev = sorted[i]
  }
  self.exit_code = 0
}

fn ExecContext::builtin_uniq(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut count_mode = false
  let mut input_file : String? = None
  for arg in args {
    match arg {
      "-c" => count_mode = true
      _ => input_file = Some(arg)
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("uniq: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)
  let mut prev = ""
  let mut count = 0
  for i = 0; i < lines.length(); i = i + 1 {
    if i == 0 || lines[i] != prev {
      if i > 0 {
        if count_mode {
          self.stdout_buf.write_string("      \{count} \{prev}\n")
        } else {
          self.stdout_buf.write_string(prev + "\n")
        }
      }
      prev = lines[i]
      count = 1
    } else {
      count += 1
    }
  }
  if lines.length() > 0 {
    if count_mode {
      self.stdout_buf.write_string("      \{count} \{prev}\n")
    } else {
      self.stdout_buf.write_string(prev + "\n")
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_cut(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut delimiter = "\t"
  let mut fields : Array[Int] = []
  let mut input_file : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == "-d" && i + 1 < args.length() {
      delimiter = args[i + 1]
      i += 2
    } else if args[i] == "-f" && i + 1 < args.length() {
      fields = parse_field_spec(args[i + 1])
      i += 2
    } else if args[i].has_prefix("-d") {
      delimiter = args[i].substring(start=2)
      i += 1
    } else if args[i].has_prefix("-f") {
      fields = parse_field_spec(args[i].substring(start=2))
      i += 1
    } else {
      input_file = Some(args[i])
      i += 1
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("cut: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)
  for line in lines {
    let parts = split_string_by_delimiter(line, delimiter)
    let out_buf = StringBuilder::new()
    let mut first = true
    for field_num in fields {
      if field_num > 0 && field_num <= parts.length() {
        if not(first) {
          out_buf.write_string(delimiter)
        }
        out_buf.write_string(parts[field_num - 1])
        first = false
      }
    }
    self.stdout_buf.write_string(out_buf.to_string() + "\n")
  }
  self.exit_code = 0
}

fn ExecContext::builtin_tee(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut append = false
  let files : Array[String] = []
  for arg in args {
    if arg == "-a" {
      append = true
    } else {
      files.push(arg)
    }
  }

  let input = self.stdin_buf
  // Write to stdout
  self.stdout_buf.write_string(input)
  // Write to files
  for file in files {
    let resolved = try {
      @fs.resolve_path(self.cwd, file)
    } catch {
      _ => file
    }
    try {
      if append {
        self.fs.append_file(resolved, input)
      } else {
        self.fs.write_file(resolved, input)
      }
    } catch {
      @fs.FsError(msg) =>
        self.stderr_buf.write_string("tee: \{msg}\n")
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_grep(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut invert = false
  let mut count_only = false
  let mut ignore_case = false
  let mut line_number = false
  let mut pattern = ""
  let mut input_file : String? = None
  let mut pattern_set = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-v" {
      invert = true
    } else if arg == "-c" {
      count_only = true
    } else if arg == "-i" {
      ignore_case = true
    } else if arg == "-n" {
      line_number = true
    } else if arg == "-e" && i + 1 < args.length() {
      i += 1
      pattern = args[i]
      pattern_set = true
    } else if not(pattern_set) {
      pattern = arg
      pattern_set = true
    } else {
      input_file = Some(arg)
    }
    i += 1
  }

  if not(pattern_set) {
    self.stderr_buf.write_string("grep: missing pattern\n")
    self.exit_code = 2
    return
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("grep: \{msg}\n")
          self.exit_code = 2
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)
  let mut match_count = 0

  for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
    let line = lines[line_idx]
    let matches = if ignore_case {
      contains_substring(to_lowercase(line), to_lowercase(pattern))
    } else {
      contains_substring(line, pattern)
    }
    let selected = if invert { not(matches) } else { matches }
    if selected {
      match_count += 1
      if not(count_only) {
        if line_number {
          self.stdout_buf.write_string(
            (line_idx + 1).to_string() + ":" + line + "\n",
          )
        } else {
          self.stdout_buf.write_string(line + "\n")
        }
      }
    }
  }
  if count_only {
    self.stdout_buf.write_string(match_count.to_string() + "\n")
  }
  self.exit_code = if match_count > 0 { 0 } else { 1 }
}

fn ExecContext::builtin_xargs(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let cmd_name = if args.length() > 0 { args[0] } else { "echo" }
  let cmd_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }

  let input_words = split_by_whitespace(self.stdin_buf)
  for word in input_words {
    cmd_args.push(word)
  }
  self.run_command(cmd_name, cmd_args)
}

fn ExecContext::builtin_date(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  self.stdout_buf.write_string("Thu Jan  1 00:00:00 UTC 1970\n")
  self.exit_code = 0
}

fn ExecContext::builtin_env(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  for k, v in self.env {
    self.stdout_buf.write_string("\{k}=\{v}\n")
  }
  self.exit_code = 0
}

fn ExecContext::builtin_which(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  for arg in args {
    if is_shell_builtin(arg) || @commands.find_command(arg) is Some(_) {
      self.stdout_buf.write_string("/usr/bin/\{arg}\n")
    } else {
      self.stderr_buf.write_string("which: no \{arg} in PATH\n")
      self.exit_code = 1
    }
  }
  if self.exit_code != 1 {
    self.exit_code = 0
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn is_shell_builtin(name : String) -> Bool {
  match name {
    "export" | "unset" | "set" | "shift" | "exit" | "return" | "break"
    | "continue" | "read" | "test" | "[" | "printf" | "eval" | "source"
    | "." | "local" | "declare" | "typeset" | ":" | "type" | "command"
    | "basename" | "dirname" | "seq" | "rev" | "tr" | "sort" | "uniq"
    | "cut" | "tee" | "grep" | "xargs" | "date" | "env" | "printenv"
    | "which" => true
    _ => false
  }
}

fn parse_int_str(s : String) -> Int {
  let mut result = 0
  let mut neg = false
  let mut start = 0
  if s.length() > 0 && s[0] == '-' {
    neg = true
    start = 1
  } else if s.length() > 0 && s[0] == '+' {
    start = 1
  }
  for i = start; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      break
    }
  }
  if neg { -result } else { result }
}

fn split_by_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' {
      let word = buf.to_string()
      if word.length() > 0 {
        result.push(word)
        buf.reset()
      }
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

fn split_lines_no_trailing(s : String) -> Array[String] {
  if s.length() == 0 {
    return []
  }
  let lines = split_lines(s)
  // Remove trailing empty line if the input ended with \n
  if lines.length() > 0 && lines[lines.length() - 1] == "" {
    let result : Array[String] = []
    for i = 0; i < lines.length() - 1; i = i + 1 {
      result.push(lines[i])
    }
    result
  } else {
    lines
  }
}

fn reverse_string(s : String) -> String {
  let buf = StringBuilder::new()
  for i = s.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn to_lowercase(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'A' && ch <= 'Z' {
      buf.write_char((ch.to_int() + 32).unsafe_to_char())
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

fn contains_substring(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  for i = 0; i <= haystack.length() - needle.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < needle.length(); j = j + 1 {
      if haystack[i + j] != needle[j] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }
  false
}

fn expand_tr_set(s : String) -> Array[Char] {
  let result : Array[Char] = []
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if i + 2 < s.length() && s[i + 1].to_int().unsafe_to_char() == '-' {
      let end_ch = s[i + 2].to_int().unsafe_to_char()
      let mut c = ch.to_int()
      while c <= end_ch.to_int() {
        result.push(c.unsafe_to_char())
        c += 1
      }
      i += 3
    } else {
      result.push(ch)
      i += 1
    }
  }
  result
}

fn tr_set_contains(set : Array[Char], ch : Char) -> Bool {
  for c in set {
    if c == ch {
      return true
    }
  }
  false
}

fn tr_translate(set1 : Array[Char], set2 : Array[Char], ch : Char) -> Char {
  for i = 0; i < set1.length(); i = i + 1 {
    if set1[i] == ch {
      if i < set2.length() {
        return set2[i]
      } else if set2.length() > 0 {
        return set2[set2.length() - 1]
      }
    }
  }
  ch
}

fn parse_field_spec(spec : String) -> Array[Int] {
  let fields : Array[Int] = []
  let parts = split_string_by_delimiter(spec, ",")
  for part in parts {
    // Handle ranges like 1-3
    if contains_substring(part, "-") {
      let range_parts = split_string_by_delimiter(part, "-")
      if range_parts.length() == 2 {
        let start = parse_int_str(range_parts[0])
        let end = parse_int_str(range_parts[1])
        for i = start; i <= end; i = i + 1 {
          fields.push(i)
        }
      }
    } else {
      fields.push(parse_int_str(part))
    }
  }
  fields
}

fn split_string_by_delimiter(s : String, delim : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let delim_len = delim.length()
  if delim_len == 0 {
    result.push(s)
    return result
  }
  let mut i = 0
  while i < s.length() {
    let mut match_found = true
    if i + delim_len <= s.length() {
      for j = 0; j < delim_len; j = j + 1 {
        if s[i + j] != delim[j] {
          match_found = false
          break
        }
      }
    } else {
      match_found = false
    }
    if match_found {
      result.push(buf.to_string())
      buf.reset()
      i += delim_len
    } else {
      buf.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  result.push(buf.to_string())
  result
}

// ============================================================================
// Test Evaluation
// ============================================================================

fn evaluate_test(args : Array[String], ctx : ExecContext) -> Bool {
  if args.length() == 0 {
    return false
  }
  if args.length() == 1 {
    // test STRING: true if string is non-empty
    return args[0].length() > 0
  }
  if args.length() == 2 {
    let op = args[0]
    let arg = args[1]
    match op {
      "-z" => return arg.length() == 0
      "-n" => return arg.length() > 0
      "-f" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(_)) => true
          _ => false
        }
      }
      "-d" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Directory(_)) => true
          _ => false
        }
      }
      "-e" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-s" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(data)) => data.content.length() > 0
          _ => false
        }
      }
      "-r" | "-w" | "-x" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-L" | "-h" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Symlink(_)) => true
          _ => false
        }
      }
      "!" => return not(evaluate_test([arg], ctx))
      _ => ()
    }
  }
  if args.length() == 3 {
    let left = args[0]
    let op = args[1]
    let right = args[2]
    match op {
      "=" | "==" => return left == right
      "!=" => return left != right
      "-eq" => return parse_int_str(left) == parse_int_str(right)
      "-ne" => return parse_int_str(left) != parse_int_str(right)
      "-lt" => return parse_int_str(left) < parse_int_str(right)
      "-le" => return parse_int_str(left) <= parse_int_str(right)
      "-gt" => return parse_int_str(left) > parse_int_str(right)
      "-ge" => return parse_int_str(left) >= parse_int_str(right)
      "-nt" | "-ot" | "-ef" => return false // File comparison not meaningful in sandbox
      _ => ()
    }
  }
  if args.length() == 4 && args[0] == "!" {
    return not(evaluate_test([args[1], args[2], args[3]], ctx))
  }
  false
}

// ============================================================================
// Printf Implementation
// ============================================================================

fn format_printf(format : String, args : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  let mut arg_idx = 0

  while i < format.length() {
    let ch = format[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < format.length() {
      let next = format[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => { buf.write_char('\n'); i += 2 }
        't' => { buf.write_char('\t'); i += 2 }
        '\\' => { buf.write_char('\\'); i += 2 }
        '"' => { buf.write_char('"'); i += 2 }
        '0' => { buf.write_char('\u0000'); i += 2 }
        _ => { buf.write_char('\\'); buf.write_char(next); i += 2 }
      }
    } else if ch == '%' && i + 1 < format.length() {
      let spec = format[i + 1].to_int().unsafe_to_char()
      match spec {
        's' => {
          if arg_idx < args.length() {
            buf.write_string(args[arg_idx])
            arg_idx += 1
          }
          i += 2
        }
        'd' => {
          if arg_idx < args.length() {
            buf.write_string(parse_int_str(args[arg_idx]).to_string())
            arg_idx += 1
          }
          i += 2
        }
        '%' => {
          buf.write_char('%')
          i += 2
        }
        _ => {
          buf.write_char('%')
          i += 1
        }
      }
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

// ============================================================================
// Redirection Helpers
// ============================================================================

fn ExecContext::apply_redirections(
  self : ExecContext,
  redirs : Array[@ast.Redirection],
  _saved_stdout : StringBuilder,
  _saved_stderr : StringBuilder
) -> Unit {
  for redir in redirs {
    match redir.op {
      @ast.RedirectOp::Input => {
        let target = self.expand_word_to_string(redir.target)
        let resolved = try {
          @fs.resolve_path(self.cwd, target)
        } catch {
          _ => target
        }
        let content = try {
          self.fs.read_file(resolved)
        } catch {
          @fs.FsError(_msg) => ""
        }
        self.stdin_buf = content
      }
      @ast.RedirectOp::HereString => {
        let content = self.expand_word_to_string(redir.target)
        self.stdin_buf = content + "\n"
      }
      @ast.RedirectOp::Output => {
        let target = self.expand_word_to_string(redir.target)
        if target == "/dev/null" {
          self.stdout_buf = StringBuilder::new()
        }
      }
      _ => ()
    }
  }
}
