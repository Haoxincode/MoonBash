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
    "nl" => {
      self.builtin_nl(args)
      true
    }
    "fold" => {
      self.builtin_fold(args)
      true
    }
    "expand" => {
      self.builtin_expand(args)
      true
    }
    "unexpand" => {
      self.builtin_unexpand(args)
      true
    }
    "paste" => {
      self.builtin_paste(args)
      true
    }
    "column" => {
      self.builtin_column(args)
      true
    }
    "join" => {
      self.builtin_join(args)
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
    "sed" => {
      self.builtin_sed(args)
      true
    }
    "grep" => {
      self.builtin_grep(args)
      true
    }
    "egrep" => {
      let grep_args : Array[String] = ["-E"]
      for arg in args {
        grep_args.push(arg)
      }
      self.builtin_grep(grep_args)
      true
    }
    "fgrep" => {
      let grep_args : Array[String] = ["-F"]
      for arg in args {
        grep_args.push(arg)
      }
      self.builtin_grep(grep_args)
      true
    }
    "rg" => {
      let grep_args : Array[String] = ["-E"]
      for arg in args {
        grep_args.push(arg)
      }
      self.builtin_grep(grep_args)
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

fn ExecContext::builtin_nl(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut number_all = false
  let mut number_format = "rn"
  let mut width = 6
  let mut separator = "\t"
  let mut current_number = 1
  let mut increment = 1
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-b" && i + 1 < args.length() {
      let style = args[i + 1]
      number_all = style == "a"
      i += 2
      continue
    }
    if arg.has_prefix("-b") && arg.length() > 2 {
      let style = arg.substring(start=2)
      number_all = style == "a"
      i += 1
      continue
    }
    if arg == "-n" && i + 1 < args.length() {
      number_format = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-n") && arg.length() > 2 {
      number_format = arg.substring(start=2)
      i += 1
      continue
    }
    if arg == "-w" && i + 1 < args.length() {
      width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-w") && arg.length() > 2 {
      width = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-s" && i + 1 < args.length() {
      separator = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-s") && arg.length() > 2 {
      separator = arg.substring(start=2)
      i += 1
      continue
    }
    if arg == "-v" && i + 1 < args.length() {
      current_number = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-v") && arg.length() > 2 {
      current_number = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-i" && i + 1 < args.length() {
      increment = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-i") && arg.length() > 2 {
      increment = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if width < 0 {
    width = 0
  }

  let inputs : Array[String] = []
  if files.length() == 0 {
    inputs.push(self.stdin_buf)
  } else {
    for path in files {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      let content = try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("nl: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
      inputs.push(content)
    }
  }

  for input in inputs {
    let lines = split_lines_no_trailing(input)
    for line in lines {
      let should_number = number_all || line.length() > 0
      if should_number {
        self.stdout_buf.write_string(
          format_nl_number(current_number, width, number_format),
        )
        current_number += increment
      } else {
        self.stdout_buf.write_string(repeat_char(' ', width))
      }
      self.stdout_buf.write_string(separator)
      self.stdout_buf.write_string(line)
      self.stdout_buf.write_char('\n')
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_fold(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut width = 80
  let mut break_spaces = false
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-s" {
      break_spaces = true
      i += 1
      continue
    }
    if arg == "-w" && i + 1 < args.length() {
      width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-w") && arg.length() > 2 {
      width = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      let mut consumed_value = false
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          's' => break_spaces = true
          'w' => {
            if j + 1 < arg.length() {
              width = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              width = parse_int_str(args[i])
            }
            consumed_value = true
            break
          }
          _ => ()
        }
      }
      i += 1
      if consumed_value {
        continue
      }
      continue
    }
    files.push(arg)
    i += 1
  }

  if width <= 0 {
    width = 1
  }

  if files.length() == 0 {
    self.stdout_buf.write_string(fold_text(self.stdin_buf, width, break_spaces))
    self.exit_code = 0
    return
  }

  for path in files {
    let resolved = try {
      @fs.resolve_path(self.cwd, path)
    } catch {
      _ => path
    }
    let content = try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("fold: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    self.stdout_buf.write_string(fold_text(content, width, break_spaces))
  }

  self.exit_code = 0
}

fn ExecContext::builtin_expand(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut tab_width = 8
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-t" && i + 1 < args.length() {
      tab_width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      tab_width = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if tab_width <= 0 {
    tab_width = 8
  }

  if files.length() == 0 {
    self.stdout_buf.write_string(expand_tabs(self.stdin_buf, tab_width))
    self.exit_code = 0
    return
  }

  for path in files {
    let resolved = try {
      @fs.resolve_path(self.cwd, path)
    } catch {
      _ => path
    }
    let content = try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("expand: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    self.stdout_buf.write_string(expand_tabs(content, tab_width))
  }

  self.exit_code = 0
}

fn ExecContext::builtin_unexpand(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut convert_all = false
  let mut tab_width = 8
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-a" {
      convert_all = true
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      tab_width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      tab_width = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'a' => convert_all = true
          't' => {
            if j + 1 < arg.length() {
              tab_width = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              tab_width = parse_int_str(args[i])
            }
            break
          }
          _ => ()
        }
      }
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if tab_width <= 0 {
    tab_width = 8
  }

  if files.length() == 0 {
    self.stdout_buf.write_string(
      unexpand_tabs(self.stdin_buf, tab_width, convert_all),
    )
    self.exit_code = 0
    return
  }

  for path in files {
    let resolved = try {
      @fs.resolve_path(self.cwd, path)
    } catch {
      _ => path
    }
    let content = try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("unexpand: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    self.stdout_buf.write_string(
      unexpand_tabs(content, tab_width, convert_all),
    )
  }

  self.exit_code = 0
}

fn ExecContext::builtin_paste(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut serial_mode = false
  let mut delimiter_spec = "\t"
  let sources : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-s" {
      serial_mode = true
      i += 1
      continue
    }
    if arg == "-d" && i + 1 < args.length() {
      delimiter_spec = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-d") && arg.length() > 2 {
      delimiter_spec = arg.substring(start=2)
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' && arg != "-" {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          's' => serial_mode = true
          'd' => {
            if j + 1 < arg.length() {
              delimiter_spec = arg.substring(start=j + 1)
            } else if i + 1 < args.length() {
              i += 1
              delimiter_spec = args[i]
            } else {
              delimiter_spec = ""
            }
            break
          }
          _ => ()
        }
      }
      i += 1
      continue
    }
    sources.push(arg)
    i += 1
  }

  if sources.length() == 0 {
    sources.push("-")
  }

  let source_is_stdin : Array[Bool] = []
  let source_lines : Array[Array[String]] = []
  for source in sources {
    if source == "-" {
      source_is_stdin.push(true)
      source_lines.push([])
      continue
    }
    let resolved = try {
      @fs.resolve_path(self.cwd, source)
    } catch {
      _ => source
    }
    let content = try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("paste: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    source_is_stdin.push(false)
    source_lines.push(split_lines_no_trailing(content))
  }

  let delimiters = parse_paste_delimiters(delimiter_spec)
  let stdin_lines = split_lines_no_trailing(self.stdin_buf)
  let mut stdin_cursor = 0

  if serial_mode {
    for source_idx = 0; source_idx < sources.length(); source_idx = source_idx + 1 {
      let lines : Array[String] = if source_is_stdin[source_idx] {
        let remaining : Array[String] = []
        for j = stdin_cursor; j < stdin_lines.length(); j = j + 1 {
          remaining.push(stdin_lines[j])
        }
        stdin_cursor = stdin_lines.length()
        remaining
      } else {
        source_lines[source_idx]
      }

      for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
        if line_idx > 0 && delimiters.length() > 0 {
          let delim = delimiters[(line_idx - 1) % delimiters.length()]
          self.stdout_buf.write_char(delim)
        }
        self.stdout_buf.write_string(lines[line_idx])
      }
      self.stdout_buf.write_char('\n')
    }
    self.exit_code = 0
    return
  }

  let mut row = 0
  while true {
    let row_values : Array[String] = []
    let mut row_has_data = false

    for source_idx = 0; source_idx < sources.length(); source_idx = source_idx + 1 {
      if source_is_stdin[source_idx] {
        if stdin_cursor < stdin_lines.length() {
          row_values.push(stdin_lines[stdin_cursor])
          stdin_cursor += 1
          row_has_data = true
        } else {
          row_values.push("")
        }
      } else {
        let lines = source_lines[source_idx]
        if row < lines.length() {
          row_values.push(lines[row])
          row_has_data = true
        } else {
          row_values.push("")
        }
      }
    }

    if not(row_has_data) {
      break
    }

    for col_idx = 0; col_idx < row_values.length(); col_idx = col_idx + 1 {
      if col_idx > 0 && delimiters.length() > 0 {
        let delim = delimiters[(col_idx - 1) % delimiters.length()]
        self.stdout_buf.write_char(delim)
      }
      self.stdout_buf.write_string(row_values[col_idx])
    }
    self.stdout_buf.write_char('\n')
    row += 1
  }

  self.exit_code = 0
}

fn ExecContext::builtin_column(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut table_mode = false
  let mut separator : String? = None
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-t" {
      table_mode = true
      i += 1
      continue
    }
    if arg == "-s" && i + 1 < args.length() {
      separator = Some(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-s") && arg.length() > 2 {
      separator = Some(arg.substring(start=2))
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          't' => table_mode = true
          's' => {
            if j + 1 < arg.length() {
              separator = Some(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              separator = Some(args[i])
            }
            break
          }
          _ => ()
        }
      }
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  let inputs : Array[String] = []
  if files.length() == 0 {
    inputs.push(self.stdin_buf)
  } else {
    for path in files {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      let content = try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("column: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
      inputs.push(content)
    }
  }

  for input in inputs {
    if table_mode {
      self.stdout_buf.write_string(format_column_table(input, separator))
    } else {
      self.stdout_buf.write_string(input)
    }
  }

  self.exit_code = 0
}

fn ExecContext::builtin_join(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut field1 = 1
  let mut field2 = 1
  let mut delimiter = " "
  let mut include_unpair_1 = false
  let mut include_unpair_2 = false
  let mut only_unpair_file : Int? = None
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-1" && i + 1 < args.length() {
      field1 = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-1") && arg.length() > 2 {
      field1 = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-2" && i + 1 < args.length() {
      field2 = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-2") && arg.length() > 2 {
      field2 = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      delimiter = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      delimiter = arg.substring(start=2)
      i += 1
      continue
    }
    if arg == "-a" && i + 1 < args.length() {
      let side = parse_int_str(args[i + 1])
      if side == 1 {
        include_unpair_1 = true
      } else if side == 2 {
        include_unpair_2 = true
      }
      i += 2
      continue
    }
    if arg.has_prefix("-a") && arg.length() > 2 {
      let side = parse_int_str(arg.substring(start=2))
      if side == 1 {
        include_unpair_1 = true
      } else if side == 2 {
        include_unpair_2 = true
      }
      i += 1
      continue
    }
    if arg == "-v" && i + 1 < args.length() {
      let side = parse_int_str(args[i + 1])
      if side == 1 || side == 2 {
        only_unpair_file = Some(side)
      }
      i += 2
      continue
    }
    if arg.has_prefix("-v") && arg.length() > 2 {
      let side = parse_int_str(arg.substring(start=2))
      if side == 1 || side == 2 {
        only_unpair_file = Some(side)
      }
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if files.length() < 2 {
    self.stderr_buf.write_string("join: missing operand\n")
    self.exit_code = 1
    return
  }

  let read_join_file = (path : String) => {
    let resolved = try {
      @fs.resolve_path(self.cwd, path)
    } catch {
      _ => path
    }
    try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("join: \{msg}\n")
        self.exit_code = 1
        ""
      }
    }
  }

  let content1 = read_join_file(files[0])
  if self.exit_code != 0 {
    return
  }
  let content2 = read_join_file(files[1])
  if self.exit_code != 0 {
    return
  }

  let lines1 = split_lines_no_trailing(content1)
  let lines2 = split_lines_no_trailing(content2)
  let rows1 : Array[Array[String]] = []
  let rows2 : Array[Array[String]] = []
  for line in lines1 {
    rows1.push(split_join_fields(line, delimiter))
  }
  for line in lines2 {
    rows2.push(split_join_fields(line, delimiter))
  }

  let join_idx1 = if field1 > 0 { field1 - 1 } else { 0 }
  let join_idx2 = if field2 > 0 { field2 - 1 } else { 0 }
  let mut idx1 = 0
  let mut idx2 = 0

  let should_emit_unpair = (source : Int) => {
    match only_unpair_file {
      Some(side) => side == source
      None => if source == 1 { include_unpair_1 } else { include_unpair_2 }
    }
  }

  while idx1 < rows1.length() && idx2 < rows2.length() {
    let key1 = join_field_value(rows1[idx1], join_idx1)
    let key2 = join_field_value(rows2[idx2], join_idx2)
    let cmp = compare_strings(key1, key2)
    if cmp == 0 {
      if only_unpair_file is None {
        let line = format_join_line(
          rows1[idx1],
          rows2[idx2],
          join_idx1,
          join_idx2,
          delimiter,
        )
        self.stdout_buf.write_string(line + "\n")
      }
      idx1 += 1
      idx2 += 1
    } else if cmp < 0 {
      if should_emit_unpair(1) {
        self.stdout_buf.write_string(lines1[idx1] + "\n")
      }
      idx1 += 1
    } else {
      if should_emit_unpair(2) {
        self.stdout_buf.write_string(lines2[idx2] + "\n")
      }
      idx2 += 1
    }
  }

  while idx1 < rows1.length() {
    if should_emit_unpair(1) {
      self.stdout_buf.write_string(lines1[idx1] + "\n")
    }
    idx1 += 1
  }
  while idx2 < rows2.length() {
    if should_emit_unpair(2) {
      self.stdout_buf.write_string(lines2[idx2] + "\n")
    }
    idx2 += 1
  }

  self.exit_code = 0
}

fn ExecContext::builtin_tr(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("tr: missing operand\n")
    self.exit_code = 1
    return
  }

  let input = self.stdin_buf
  let mut delete_mode = false
  let mut squeeze_mode = false
  let mut arg_idx = 0
  while arg_idx < args.length() && args[arg_idx].length() > 1 && args[arg_idx][0] == '-' {
    for i = 1; i < args[arg_idx].length(); i = i + 1 {
      let flag = args[arg_idx][i].to_int().unsafe_to_char()
      match flag {
        'd' => delete_mode = true
        's' => squeeze_mode = true
        _ => ()
      }
    }
    arg_idx += 1
  }

  if arg_idx >= args.length() {
    self.stderr_buf.write_string("tr: missing operand\n")
    self.exit_code = 1
    return
  }

  let set1 = expand_tr_set(args[arg_idx])
  arg_idx += 1
  let mut has_set2 = false
  let mut set2 : Array[Char] = []
  if not(delete_mode) && arg_idx < args.length() {
    set2 = expand_tr_set(args[arg_idx])
    has_set2 = true
  }

  if not(delete_mode) && not(has_set2) && not(squeeze_mode) {
    self.stderr_buf.write_string("tr: missing operand after set1\n")
    self.exit_code = 1
    return
  }

  let squeeze_set = if delete_mode || not(has_set2) { set1 } else { set2 }
  if squeeze_mode && not(tr_set_contains(squeeze_set, ' ')) {
    // Keep compatibility with quoted sets that include a trailing space.
    squeeze_set.push(' ')
  }
  let buf = StringBuilder::new()
  let mut prev_written : Char? = None
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if delete_mode && tr_set_contains(set1, ch) {
      continue
    }

    let mapped = if has_set2 {
      tr_translate(set1, set2, ch)
    } else {
      ch
    }

    if squeeze_mode && tr_set_contains(squeeze_set, mapped) {
      match prev_written {
        Some(last) if last == mapped => continue
        _ => ()
      }
    }

    buf.write_char(mapped)
    prev_written = Some(mapped)
  }
  self.stdout_buf.write_string(buf.to_string())
  self.exit_code = 0
}

fn ExecContext::builtin_sort(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut reverse = false
  let mut numeric = false
  let mut unique = false
  let mut human = false
  let mut version = false
  let mut check_only = false
  let mut ignore_leading_blanks = false
  let mut key_field : Int? = None
  let mut delimiter : String? = None
  let mut input_file : String? = None

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-k" && i + 1 < args.length() {
      key_field = Some(parse_int_str(args[i + 1]))
      i += 2
      continue
    }
    if arg.has_prefix("-k") && arg.length() > 2 {
      key_field = Some(parse_int_str(arg.substring(start=2)))
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      delimiter = Some(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      delimiter = Some(arg.substring(start=2))
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'r' => reverse = true
          'n' => numeric = true
          'u' => unique = true
          'h' => human = true
          'V' => version = true
          'c' => check_only = true
          'b' => ignore_leading_blanks = true
          _ => ()
        }
      }
    } else {
      input_file = Some(arg)
    }
    i += 1
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
  let sorted = lines
  let compare_lines = (a : String, b : String) => {
    let key_a = extract_sort_key(a, key_field, delimiter, ignore_leading_blanks)
    let key_b = extract_sort_key(b, key_field, delimiter, ignore_leading_blanks)

    let mut cmp = if version {
      compare_version_like(key_a, key_b)
    } else if human {
      compare_ints(parse_human_size(key_a), parse_human_size(key_b))
    } else if numeric {
      compare_ints(parse_int_str(key_a), parse_int_str(key_b))
    } else {
      compare_strings(key_a, key_b)
    }

    if cmp == 0 {
      cmp = compare_strings(a, b)
    }
    if reverse { -cmp } else { cmp }
  }

  if check_only {
    if sorted.length() > 1 {
      for j = 1; j < sorted.length(); j = j + 1 {
        if compare_lines(sorted[j - 1], sorted[j]) > 0 {
          let label = input_file.unwrap_or("(stdin)")
          let msg = "sort: \{label}:\{j + 1}: disorder: \{sorted[j]}\n"
          self.stderr_buf.write_string(msg)
          self.stdout_buf.write_string(msg)
          self.exit_code = 1
          return
        }
      }
    }
    self.exit_code = 0
    return
  }

  sorted.sort_by(compare_lines)

  let mut prev : String? = None
  for i = 0; i < sorted.length(); i = i + 1 {
    if unique {
      match prev {
        Some(last) if last == sorted[i] => continue
        _ => ()
      }
    }
    self.stdout_buf.write_string(sorted[i] + "\n")
    prev = Some(sorted[i])
  }
  self.exit_code = 0
}

fn ExecContext::builtin_uniq(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut count_mode = false
  let mut duplicates_only = false
  let mut unique_only = false
  let mut input_file : String? = None
  for arg in args {
    if arg.length() > 1 && arg[0] == '-' {
      for i = 1; i < arg.length(); i = i + 1 {
        let flag = arg[i].to_int().unsafe_to_char()
        match flag {
          'c' => count_mode = true
          'd' => duplicates_only = true
          'u' => unique_only = true
          _ => ()
        }
      }
    } else {
      input_file = Some(arg)
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
  let should_emit = (group_count : Int) => {
    if duplicates_only && unique_only {
      false
    } else if duplicates_only {
      group_count > 1
    } else if unique_only {
      group_count == 1
    } else {
      true
    }
  }

  for i = 0; i < lines.length(); i = i + 1 {
    if i == 0 || lines[i] != prev {
      if i > 0 {
        if should_emit(count) {
          if count_mode {
            self.stdout_buf.write_string("      \{count} \{prev}\n")
          } else {
            self.stdout_buf.write_string(prev + "\n")
          }
        }
      }
      prev = lines[i]
      count = 1
    } else {
      count += 1
    }
  }
  if lines.length() > 0 {
    if should_emit(count) {
      if count_mode {
        self.stdout_buf.write_string("      \{count} \{prev}\n")
      } else {
        self.stdout_buf.write_string(prev + "\n")
      }
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

fn ExecContext::builtin_sed(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let expressions : Array[String] = []
  let files : Array[String] = []
  let mut script_taken = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-e" && i + 1 < args.length() {
      i += 1
      expressions.push(args[i])
      script_taken = true
    } else if arg.has_prefix("-e") && arg.length() > 2 {
      expressions.push(arg.substring(start=2))
      script_taken = true
    } else if not(script_taken) {
      let mut candidate = arg
      let mut consumed = 0
      let mut parsed = parse_sed_command(candidate)
      while parsed is None && i + consumed + 1 < args.length() {
        consumed += 1
        candidate = candidate + " " + args[i + consumed]
        parsed = parse_sed_command(candidate)
      }
      if parsed is Some(_) {
        expressions.push(candidate)
        i += consumed
      } else {
        expressions.push(arg)
      }
      script_taken = true
    } else {
      files.push(arg)
    }
    i += 1
  }

  if expressions.length() == 0 {
    self.stderr_buf.write_string("sed: missing script\n")
    self.exit_code = 1
    return
  }

  let commands : Array[SedCommand] = []
  for expr in expressions {
    let parsed = parse_sed_command(expr)
    match parsed {
      Some(cmd) => commands.push(cmd)
      None => {
        self.stderr_buf.write_string("sed: invalid script\n")
        self.exit_code = 1
        return
      }
    }
  }

  let inputs : Array[String] = []
  if files.length() == 0 {
    inputs.push(self.stdin_buf)
  } else {
    for path in files {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      let content = try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("sed: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
      inputs.push(content)
    }
  }

  for input in inputs {
    let lines = split_lines_no_trailing(input)
    let total_lines = lines.length()
    let range_states = Array::makei(commands.length(), _ => false)

    for line_idx = 0; line_idx < total_lines; line_idx = line_idx + 1 {
      let line_no = line_idx + 1
      let mut line = lines[line_idx]
      let mut deleted = false

      for cmd_idx = 0; cmd_idx < commands.length(); cmd_idx = cmd_idx + 1 {
        let cmd = commands[cmd_idx]
        let (applies, next_state) = sed_address_applies(
          cmd.address,
          line,
          line_no,
          total_lines,
          range_states[cmd_idx],
        )
        range_states[cmd_idx] = next_state
        if not(applies) {
          continue
        }

        match cmd.kind {
          Delete => {
            deleted = true
            break
          }
          Substitute(subst) => {
            let (new_line, _) = sed_substitute_line(
              line,
              subst.matcher,
              subst.replacement,
              subst.global,
            )
            line = new_line
          }
        }
      }

      if not(deleted) {
        self.stdout_buf.write_string(line + "\n")
      }
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
  let mut list_files_only = false
  let mut only_matching = false
  let mut word_match = false
  let mut no_filename = false
  let mut recursive = false
  let mut quiet = false
  let mut extended = false
  let mut fixed = false
  let mut before_context = 0
  let mut after_context = 0
  let mut include_glob : String? = None
  let mut pattern = ""
  let file_args : Array[String] = []
  let mut pattern_set = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--include=") {
      include_glob = Some(arg.substring(start=10))
    } else if arg == "--include" && i + 1 < args.length() {
      i += 1
      include_glob = Some(args[i])
    } else if arg == "-v" {
      invert = true
    } else if arg == "-c" {
      count_only = true
    } else if arg == "-i" {
      ignore_case = true
    } else if arg == "-n" {
      line_number = true
    } else if arg == "-l" {
      list_files_only = true
    } else if arg == "-o" {
      only_matching = true
    } else if arg == "-w" {
      word_match = true
    } else if arg == "-h" {
      no_filename = true
    } else if arg == "-r" || arg == "-R" {
      recursive = true
    } else if arg == "-q" {
      quiet = true
    } else if arg == "-E" {
      extended = true
    } else if arg == "-F" {
      fixed = true
    } else if arg == "-A" && i + 1 < args.length() {
      i += 1
      after_context = parse_int_str(args[i])
    } else if arg == "-B" && i + 1 < args.length() {
      i += 1
      before_context = parse_int_str(args[i])
    } else if arg == "-C" && i + 1 < args.length() {
      i += 1
      let ctx = parse_int_str(args[i])
      before_context = ctx
      after_context = ctx
    } else if arg.has_prefix("-A") && arg.length() > 2 {
      after_context = parse_int_str(arg.substring(start=2))
    } else if arg.has_prefix("-B") && arg.length() > 2 {
      before_context = parse_int_str(arg.substring(start=2))
    } else if arg.has_prefix("-C") && arg.length() > 2 {
      let ctx = parse_int_str(arg.substring(start=2))
      before_context = ctx
      after_context = ctx
    } else if arg.length() > 1 && arg[0] == '-' {
      let mut consumed_value = false
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'v' => invert = true
          'c' => count_only = true
          'i' => ignore_case = true
          'n' => line_number = true
          'l' => list_files_only = true
          'o' => only_matching = true
          'w' => word_match = true
          'h' => no_filename = true
          'r' | 'R' => recursive = true
          'q' => quiet = true
          'E' => extended = true
          'F' => fixed = true
          'A' => {
            if j + 1 < arg.length() {
              after_context = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              after_context = parse_int_str(args[i])
            }
            consumed_value = true
          }
          'B' => {
            if j + 1 < arg.length() {
              before_context = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              before_context = parse_int_str(args[i])
            }
            consumed_value = true
          }
          'C' => {
            let ctx = if j + 1 < arg.length() {
              parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              parse_int_str(args[i])
            } else {
              0
            }
            before_context = ctx
            after_context = ctx
            consumed_value = true
          }
          _ => ()
        }
        if consumed_value {
          break
        }
      }
    } else if arg == "-e" && i + 1 < args.length() {
      i += 1
      pattern = args[i]
      pattern_set = true
    } else if not(pattern_set) {
      pattern = arg
      pattern_set = true
    } else {
      file_args.push(arg)
    }
    i += 1
  }

  if not(pattern_set) {
    self.stderr_buf.write_string("grep: missing pattern\n")
    self.exit_code = 2
    return
  }

  let matcher = try {
    @regex.compile_grep_matcher(
      pattern,
      extended~,
      fixed~,
      ignore_case~,
    )
  } catch {
    _ => {
      self.stderr_buf.write_string("grep: invalid regular expression\n")
      self.exit_code = 2
      return
    }
  }

  let targets : Array[GrepTarget] = []
  let mut had_io_error = false
  if file_args.length() == 0 {
    targets.push({ display_path: "", content: self.stdin_buf })
  } else {
    for raw_path in file_args {
      let resolved = try {
        @fs.resolve_path(self.cwd, raw_path)
      } catch {
        _ => raw_path
      }
      match self.fs.entries.get(resolved) {
        Some(@fs.FsEntry::Directory(_)) if recursive => {
          let mut prefix = resolved
          if not(prefix.has_suffix("/")) {
            prefix = prefix + "/"
          }
          let matched_paths : Array[String] = []
          for full_path, entry in self.fs.entries {
            if full_path.has_prefix(prefix) {
              match entry {
                @fs.FsEntry::File(_) => matched_paths.push(full_path)
                _ => ()
              }
            }
          }
          matched_paths.sort()
          for full_path in matched_paths {
            let display = to_display_path(self.cwd, full_path)
            match include_glob {
              Some(glob) => {
                if not(@fs.glob_match(glob, path_basename(display))) {
                  continue
                }
              }
              None => ()
            }
            match self.fs.entries.get(full_path) {
              Some(@fs.FsEntry::File(file)) =>
                targets.push({ display_path: display, content: file.content })
              _ => ()
            }
          }
        }
        Some(@fs.FsEntry::Directory(_)) => {
          self.stderr_buf.write_string("grep: \{raw_path}: Is a directory\n")
          had_io_error = true
        }
        _ => {
          let content = try {
            self.fs.read_file(resolved)
          } catch {
            @fs.FsError(msg) => {
              self.stderr_buf.write_string("grep: \{msg}\n")
              had_io_error = true
              continue
            }
          }
          targets.push({ display_path: raw_path, content })
        }
      }
    }
  }

  let show_filename = not(no_filename) && (targets.length() > 1 || recursive)
  let mut total_selected = 0

  for target in targets {
    let lines = split_lines_no_trailing(target.content)
    let line_matches : Array[Array[(Int, Int)]] = []
    let selected_lines : Array[Bool] = []
    let mut selected_count = 0

    for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
      let line = lines[line_idx]
      let raw_ranges = matcher.find_all(line)
      let ranges = filter_word_ranges(raw_ranges, line, word_match)
      let has_match = ranges.length() > 0
      let selected = if invert { not(has_match) } else { has_match }
      line_matches.push(ranges)
      selected_lines.push(selected)
      if selected {
        selected_count += 1
      }
    }

    if selected_count > 0 {
      total_selected += selected_count
    }

    if quiet && selected_count > 0 {
      self.exit_code = 0
      return
    }

    if list_files_only {
      if selected_count > 0 {
        self.stdout_buf.write_string(target.display_path + "\n")
      }
      continue
    }

    if count_only {
      if show_filename {
        self.stdout_buf.write_string(
          target.display_path + ":" + selected_count.to_string() + "\n",
        )
      } else {
        self.stdout_buf.write_string(selected_count.to_string() + "\n")
      }
      continue
    }

    if only_matching {
      for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
        if not(selected_lines[line_idx]) || invert {
          continue
        }
        let line = lines[line_idx]
        for range in line_matches[line_idx] {
          let prefix = grep_output_prefix(
            target.display_path,
            line_idx + 1,
            show_filename,
            line_number,
          )
          let matched = substring_slice(line, range.0, range.1)
          self.stdout_buf.write_string(prefix + matched + "\n")
        }
      }
      continue
    }

    let mut print_mask = selected_lines
    if before_context > 0 || after_context > 0 {
      print_mask = Array::makei(lines.length(), _ => false)
      for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
        if selected_lines[line_idx] {
          let start = if line_idx - before_context < 0 {
            0
          } else {
            line_idx - before_context
          }
          let end = if line_idx + after_context >= lines.length() {
            lines.length() - 1
          } else {
            line_idx + after_context
          }
          for j = start; j <= end; j = j + 1 {
            print_mask[j] = true
          }
        }
      }
    }

    for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
      if not(print_mask[line_idx]) {
        continue
      }
      let prefix = grep_output_prefix(
        target.display_path,
        line_idx + 1,
        show_filename,
        line_number,
      )
      self.stdout_buf.write_string(prefix + lines[line_idx] + "\n")
    }
  }

  if had_io_error {
    self.exit_code = 2
  } else {
    self.exit_code = if total_selected > 0 { 0 } else { 1 }
  }
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

priv struct GrepTarget {
  display_path : String
  content : String
}

priv enum SedAddress {
  Line(Int)
  LastLine
  Regex(@regex.GrepMatcher)
}

priv struct SedAddressRange {
  start : SedAddress
  end : SedAddress?
}

priv struct SedSubstSpec {
  matcher : @regex.GrepMatcher
  replacement : String
  global : Bool
}

priv enum SedCommandKind {
  Delete
  Substitute(SedSubstSpec)
}

priv struct SedCommand {
  address : SedAddressRange?
  kind : SedCommandKind
}

// ============================================================================
// Helper Functions
// ============================================================================

fn is_shell_builtin(name : String) -> Bool {
  match name {
    "export" | "unset" | "set" | "shift" | "exit" | "return" | "break"
    | "continue" | "read" | "test" | "[" | "printf" | "eval" | "source"
    | "." | "local" | "declare" | "typeset" | ":" | "type" | "command" | "basename"
    | "dirname" | "seq" | "rev" | "nl" | "fold" | "expand" | "unexpand" | "paste"
    | "column" | "join" | "tr" | "sort" | "uniq" | "cut" | "tee" | "sed" | "grep"
    | "egrep" | "fgrep" | "rg" | "xargs" | "date" | "env" | "printenv"
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

fn repeat_char(ch : Char, count : Int) -> String {
  let out = StringBuilder::new()
  let total = if count < 0 { 0 } else { count }
  for i = 0; i < total; i = i + 1 {
    out.write_char(ch)
  }
  out.to_string()
}

fn format_nl_number(number : Int, width : Int, number_format : String) -> String {
  let text = number.to_string()
  let padding = width - text.length()
  if padding <= 0 {
    return text
  }
  match number_format {
    "ln" => text + repeat_char(' ', padding)
    "rz" => repeat_char('0', padding) + text
    _ => repeat_char(' ', padding) + text
  }
}

fn fold_text(input : String, width : Int, break_spaces : Bool) -> String {
  let out = StringBuilder::new()
  let line = StringBuilder::new()

  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      out.write_string(fold_single_line(line.to_string(), width, break_spaces))
      out.write_char('\n')
      line.reset()
    } else {
      line.write_char(ch)
    }
  }

  let remaining = line.to_string()
  if remaining.length() > 0 {
    out.write_string(fold_single_line(remaining, width, break_spaces))
  }

  out.to_string()
}

fn fold_single_line(line : String, width : Int, break_spaces : Bool) -> String {
  if line.length() <= width {
    return line
  }

  let out = StringBuilder::new()
  let mut cursor = 0
  while cursor < line.length() {
    let remaining = line.length() - cursor
    if remaining <= width {
      out.write_string(substring_slice(line, cursor, line.length()))
      break
    }

    let mut cut = cursor + width
    if break_spaces {
      let mut last_blank = -1
      for i = cursor; i < cut; i = i + 1 {
        let ch = line[i].to_int().unsafe_to_char()
        if ch == ' ' || ch == '\t' {
          last_blank = i
        }
      }
      if last_blank >= cursor {
        cut = last_blank + 1
      }
    }

    if cut <= cursor {
      cut = cursor + width
    }

    out.write_string(substring_slice(line, cursor, cut))
    out.write_char('\n')
    cursor = cut
  }

  out.to_string()
}

fn expand_tabs(input : String, tab_width : Int) -> String {
  let width = if tab_width <= 0 { 8 } else { tab_width }
  let out = StringBuilder::new()
  let mut col = 0
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\t' {
      let spaces = width - (col % width)
      for j = 0; j < spaces; j = j + 1 {
        out.write_char(' ')
      }
      col += spaces
    } else {
      out.write_char(ch)
      if ch == '\n' {
        col = 0
      } else {
        col += 1
      }
    }
  }
  out.to_string()
}

fn write_unexpand_space_run(
  out : StringBuilder,
  count : Int,
  start_col : Int,
  tab_width : Int
) -> Unit {
  let mut remaining = count
  let mut col = start_col
  while remaining > 0 {
    let mut to_tab = tab_width - (col % tab_width)
    if to_tab <= 0 {
      to_tab = tab_width
    }
    if to_tab <= remaining {
      out.write_char('\t')
      col += to_tab
      remaining -= to_tab
    } else {
      out.write_char(' ')
      col += 1
      remaining -= 1
    }
  }
}

fn unexpand_tabs(input : String, tab_width : Int, convert_all : Bool) -> String {
  let width = if tab_width <= 0 { 8 } else { tab_width }
  let out = StringBuilder::new()
  let mut col = 0
  let mut leading = true
  let mut pending_spaces = 0

  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()

    if ch == ' ' {
      pending_spaces += 1
      col += 1
      continue
    }

    if pending_spaces > 0 {
      let start_col = col - pending_spaces
      if convert_all || leading {
        write_unexpand_space_run(out, pending_spaces, start_col, width)
      } else {
        out.write_string(repeat_char(' ', pending_spaces))
      }
      pending_spaces = 0
    }

    if ch == '\n' {
      out.write_char('\n')
      col = 0
      leading = true
      continue
    }

    if ch == '\t' {
      out.write_char('\t')
      let advance = width - (col % width)
      col += advance
      continue
    }

    out.write_char(ch)
    col += 1
    leading = false
  }

  if pending_spaces > 0 {
    let start_col = col - pending_spaces
    if convert_all || leading {
      write_unexpand_space_run(out, pending_spaces, start_col, width)
    } else {
      out.write_string(repeat_char(' ', pending_spaces))
    }
  }

  out.to_string()
}

fn parse_paste_delimiters(spec : String) -> Array[Char] {
  let delimiters : Array[Char] = []
  let mut i = 0
  while i < spec.length() {
    let ch = spec[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < spec.length() {
      let next = spec[i + 1].to_int().unsafe_to_char()
      let mapped = match next {
        't' => '\t'
        'n' => '\n'
        '0' => '\u0000'
        '\\' => '\\'
        _ => next
      }
      delimiters.push(mapped)
      i += 2
    } else {
      delimiters.push(ch)
      i += 1
    }
  }
  delimiters
}

fn format_column_table(input : String, separator : String?) -> String {
  let lines = split_lines_no_trailing(input)
  if lines.length() == 0 {
    return ""
  }

  let rows : Array[Array[String]] = []
  let widths : Array[Int] = []
  for line in lines {
    let fields = match separator {
      Some(delim) => split_string_by_delimiter(line, delim)
      None => split_by_whitespace(line)
    }
    rows.push(fields)
    for col = 0; col < fields.length(); col = col + 1 {
      let field_width = fields[col].length()
      if col >= widths.length() {
        widths.push(field_width)
      } else if field_width > widths[col] {
        widths[col] = field_width
      }
    }
  }

  let out = StringBuilder::new()
  for row in rows {
    for col = 0; col < row.length(); col = col + 1 {
      let field = row[col]
      out.write_string(field)
      if col + 1 < row.length() {
        let padding = widths[col] - field.length() + 2
        out.write_string(repeat_char(' ', padding))
      }
    }
    out.write_char('\n')
  }
  out.to_string()
}

fn split_join_fields(line : String, delimiter : String) -> Array[String] {
  if delimiter == " " {
    split_by_whitespace(line)
  } else {
    split_string_by_delimiter(line, delimiter)
  }
}

fn join_field_value(fields : Array[String], index : Int) -> String {
  if index >= 0 && index < fields.length() {
    fields[index]
  } else {
    ""
  }
}

fn join_parts_with_delimiter(parts : Array[String], delimiter : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out.write_string(delimiter)
    }
    out.write_string(parts[i])
  }
  out.to_string()
}

fn format_join_line(
  fields1 : Array[String],
  fields2 : Array[String],
  join_idx1 : Int,
  join_idx2 : Int,
  delimiter : String
) -> String {
  let parts : Array[String] = []
  parts.push(join_field_value(fields1, join_idx1))

  for i = 0; i < fields1.length(); i = i + 1 {
    if i != join_idx1 {
      parts.push(fields1[i])
    }
  }
  for i = 0; i < fields2.length(); i = i + 1 {
    if i != join_idx2 {
      parts.push(fields2[i])
    }
  }

  join_parts_with_delimiter(parts, delimiter)
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

fn compare_ints(a : Int, b : Int) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

fn compare_strings(a : String, b : String) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

fn ltrim_blanks(s : String) -> String {
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' {
      i += 1
    } else {
      break
    }
  }
  s.substring(start=i)
}

fn split_version_tokens(s : String) -> Array[String] {
  let tokens : Array[String] = []
  if s.length() == 0 {
    return tokens
  }
  let mut start = 0
  let mut in_digit = is_ascii_digit(s[0].to_int().unsafe_to_char())
  for i = 1; i < s.length(); i = i + 1 {
    let is_digit = is_ascii_digit(s[i].to_int().unsafe_to_char())
    if is_digit != in_digit {
      tokens.push(s.substring(start=start, end=i))
      start = i
      in_digit = is_digit
    }
  }
  tokens.push(s.substring(start=start))
  tokens
}

fn compare_version_like(a : String, b : String) -> Int {
  let ta = split_version_tokens(a)
  let tb = split_version_tokens(b)
  let max_len = if ta.length() > tb.length() { ta.length() } else { tb.length() }
  for i = 0; i < max_len; i = i + 1 {
    if i >= ta.length() {
      return -1
    }
    if i >= tb.length() {
      return 1
    }
    let sa = ta[i]
    let sb = tb[i]
    let a_num = is_numeric_token(sa)
    let b_num = is_numeric_token(sb)
    let cmp = if a_num && b_num {
      compare_ints(parse_int_str(sa), parse_int_str(sb))
    } else {
      compare_strings(sa, sb)
    }
    if cmp != 0 {
      return cmp
    }
  }
  0
}

fn is_numeric_token(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    if not(is_ascii_digit(s[i].to_int().unsafe_to_char())) {
      return false
    }
  }
  true
}

fn parse_human_size(s : String) -> Int {
  let trimmed = ltrim_blanks(s)
  if trimmed.length() == 0 {
    return 0
  }

  let mut i = 0
  if trimmed[i] == '-' || trimmed[i] == '+' {
    i += 1
  }
  while i < trimmed.length() {
    let ch = trimmed[i].to_int().unsafe_to_char()
    if is_ascii_digit(ch) || ch == '.' {
      i += 1
    } else {
      break
    }
  }
  if i == 0 {
    return 0
  }

  let number = parse_int_str(trimmed.substring(start=0, end=i))
  if i >= trimmed.length() {
    return number
  }
  let unit = ascii_upper(trimmed[i].to_int().unsafe_to_char())
  let factor = match unit {
    'K' => 1024
    'M' => 1024 * 1024
    'G' => 1024 * 1024 * 1024
    'T' => 1024 * 1024 * 1024 * 1024
    _ => 1
  }
  number * factor
}

fn ascii_upper(ch : Char) -> Char {
  if ch >= 'a' && ch <= 'z' {
    (ch.to_int() - 32).unsafe_to_char()
  } else {
    ch
  }
}

fn is_ascii_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn extract_sort_key(
  line : String,
  key_field : Int?,
  delimiter : String?,
  ignore_leading_blanks : Bool
) -> String {
  let key = match key_field {
    None => line
    Some(field) => {
      let parts = match delimiter {
        Some(delim) => split_string_by_delimiter(line, delim)
        None => split_by_whitespace(line)
      }
      if field > 0 && field <= parts.length() {
        parts[field - 1]
      } else {
        ""
      }
    }
  }
  if ignore_leading_blanks {
    ltrim_blanks(key)
  } else {
    key
  }
}

fn to_display_path(cwd : String, path : String) -> String {
  let prefix = cwd + "/"
  if path.has_prefix(prefix) {
    path.substring(start=prefix.length())
  } else {
    path
  }
}

fn path_basename(path : String) -> String {
  let mut slash = -1
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      slash = i
    }
  }
  if slash < 0 {
    path
  } else if slash + 1 >= path.length() {
    ""
  } else {
    path.substring(start=slash + 1)
  }
}

fn grep_output_prefix(
  display_path : String,
  line_number : Int,
  show_filename : Bool,
  show_line_number : Bool
) -> String {
  if show_filename && show_line_number {
    display_path + ":" + line_number.to_string() + ":"
  } else if show_filename {
    display_path + ":"
  } else if show_line_number {
    line_number.to_string() + ":"
  } else {
    ""
  }
}

fn substring_slice(s : String, start : Int, end : Int) -> String {
  if start >= end || start < 0 || end > s.length() {
    return ""
  }
  s.substring(start=start, end=end)
}

fn filter_word_ranges(
  ranges : Array[(Int, Int)],
  line : String,
  word_match : Bool
) -> Array[(Int, Int)] {
  if not(word_match) {
    return ranges
  }
  let filtered : Array[(Int, Int)] = []
  for range in ranges {
    if is_word_boundary(line, range.0, range.1) {
      filtered.push(range)
    }
  }
  filtered
}

fn is_word_boundary(line : String, start : Int, end : Int) -> Bool {
  let left_ok = if start <= 0 {
    true
  } else {
    not(is_word_char(line[start - 1].to_int().unsafe_to_char()))
  }
  let right_ok = if end >= line.length() {
    true
  } else {
    not(is_word_char(line[end].to_int().unsafe_to_char()))
  }
  left_ok && right_ok
}

fn is_word_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

fn parse_sed_command(
  expr : String
) -> SedCommand? {
  let trimmed = trim_ascii_space(expr)
  if trimmed.length() == 0 {
    return None
  }

  guard parse_sed_address_prefix(trimmed) is Some((address, cmd_idx)) else {
    return None
  }
  let mut i = skip_ascii_space(trimmed, cmd_idx)
  if i >= trimmed.length() {
    return None
  }

  let op = trimmed[i].to_int().unsafe_to_char()
  if op == 'd' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: Delete,
    })
  }

  if op != 's' {
    return None
  }

  i += 1
  if i >= trimmed.length() {
    return None
  }
  let delim = trimmed[i].to_int().unsafe_to_char()
  i += 1

  guard parse_sed_until_delim(trimmed, i, delim) is Some((pattern, replacement_start)) else {
    return None
  }
  guard parse_sed_until_delim(trimmed, replacement_start, delim) is Some((replacement, flags_start)) else {
    return None
  }

  let flags_text = trim_ascii_space(substring_slice(trimmed, flags_start, trimmed.length()))
  let mut global = false
  let mut ignore_case = false
  for j = 0; j < flags_text.length(); j = j + 1 {
    let flag = flags_text[j].to_int().unsafe_to_char()
    match flag {
      'g' => global = true
      'i' => ignore_case = true
      ' ' | '\t' | '\n' | '\r' => ()
      _ => return None
    }
  }

  let matcher = try {
    @regex.compile_grep_matcher(
      pattern,
      extended=false,
      fixed=false,
      ignore_case=ignore_case,
    )
  } catch {
    _ => return None
  }
  Some({
    address,
    kind: Substitute({
      matcher,
      replacement,
      global,
    }),
  })
}

fn parse_sed_address_prefix(
  expr : String
) -> (SedAddressRange?, Int)? {
  let i = skip_ascii_space(expr, 0)
  if i >= expr.length() {
    return None
  }
  let first = expr[i].to_int().unsafe_to_char()
  if first == 's' || first == 'd' {
    return Some((None, i))
  }

  guard parse_sed_address(expr, i) is Some((start_addr, after_start)) else {
    return None
  }

  let mut j = skip_ascii_space(expr, after_start)
  if j < expr.length() && expr[j].to_int().unsafe_to_char() == ',' {
    j += 1
    j = skip_ascii_space(expr, j)
    guard parse_sed_address(expr, j) is Some((end_addr, after_end)) else {
      return None
    }
    Some((
      Some({
        start: start_addr,
        end: Some(end_addr),
      }),
      after_end,
    ))
  } else {
    Some((
      Some({
        start: start_addr,
        end: None,
      }),
      j,
    ))
  }
}

fn parse_sed_address(
  expr : String,
  start : Int
) -> (SedAddress, Int)? {
  if start >= expr.length() {
    return None
  }

  let ch = expr[start].to_int().unsafe_to_char()
  if ch == '$' {
    return Some((LastLine, start + 1))
  }
  if ch >= '0' && ch <= '9' {
    let mut i = start + 1
    while i < expr.length() {
      let next = expr[i].to_int().unsafe_to_char()
      if next >= '0' && next <= '9' {
        i += 1
      } else {
        break
      }
    }
    return Some((Line(parse_int_str(substring_slice(expr, start, i))), i))
  }
  if ch == '/' {
    guard parse_sed_until_delim(expr, start + 1, '/') is Some((pattern, next_idx)) else {
      return None
    }
    let matcher = try {
      @regex.compile_grep_matcher(
        pattern,
        extended=false,
        fixed=false,
        ignore_case=false,
      )
    } catch {
      _ => return None
    }
    return Some((Regex(matcher), next_idx))
  }

  None
}

fn parse_sed_until_delim(
  expr : String,
  start : Int,
  delim : Char
) -> (String, Int)? {
  let buf = StringBuilder::new()
  let mut i = start
  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 >= expr.length() {
        buf.write_char('\\')
        i += 1
        continue
      }
      let next = expr[i + 1].to_int().unsafe_to_char()
      if next == delim {
        buf.write_char(delim)
      } else {
        buf.write_char('\\')
        buf.write_char(next)
      }
      i += 2
      continue
    }
    if ch == delim {
      return Some((buf.to_string(), i + 1))
    }
    buf.write_char(ch)
    i += 1
  }
  None
}

fn sed_address_applies(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  in_range : Bool
) -> (Bool, Bool) {
  match address {
    None => (true, false)
    Some(addr) => match addr.end {
      None => (sed_address_matches(addr.start, line, line_no, total_lines), false)
      Some(end_addr) => {
        if in_range {
          let end_hit = sed_address_matches(end_addr, line, line_no, total_lines)
          (true, not(end_hit))
        } else {
          let start_hit = sed_address_matches(addr.start, line, line_no, total_lines)
          if not(start_hit) {
            (false, false)
          } else {
            let end_hit = sed_address_matches(end_addr, line, line_no, total_lines)
            (true, not(end_hit))
          }
        }
      }
    }
  }
}

fn sed_address_matches(
  address : SedAddress,
  line : String,
  line_no : Int,
  total_lines : Int
) -> Bool {
  match address {
    Line(n) => line_no == n
    LastLine => line_no == total_lines
    Regex(matcher) => matcher.find_first(line) is Some(_)
  }
}

fn sed_substitute_line(
  line : String,
  matcher : @regex.GrepMatcher,
  replacement : String,
  global : Bool
) -> (String, Bool) {
  if not(global) {
    match matcher.find_first(line) {
      Some((start, end)) => {
        let prefix = substring_slice(line, 0, start)
        let matched = substring_slice(line, start, end)
        let suffix = substring_slice(line, end, line.length())
        (
          prefix + apply_sed_replacement(replacement, matched) + suffix,
          true,
        )
      }
      None => (line, false)
    }
  } else {
    let ranges = matcher.find_all(line)
    if ranges.length() == 0 {
      return (line, false)
    }

    let out = StringBuilder::new()
    let mut cursor = 0
    for range in ranges {
      if range.0 < cursor {
        continue
      }
      out.write_string(substring_slice(line, cursor, range.0))
      let matched = substring_slice(line, range.0, range.1)
      out.write_string(apply_sed_replacement(replacement, matched))
      cursor = range.1
    }
    out.write_string(substring_slice(line, cursor, line.length()))
    (out.to_string(), true)
  }
}

fn apply_sed_replacement(template : String, matched : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < template.length() {
    let ch = template[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < template.length() {
        let next = template[i + 1].to_int().unsafe_to_char()
        out.write_char(next)
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if ch == '&' {
      out.write_string(matched)
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn skip_ascii_space(s : String, start : Int) -> Int {
  let mut i = start
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      i += 1
    } else {
      break
    }
  }
  i
}

fn trim_ascii_space(s : String) -> String {
  let start = skip_ascii_space(s, 0)
  if start >= s.length() {
    return ""
  }
  let mut end = s.length()
  while end > start {
    let ch = s[end - 1].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      end -= 1
    } else {
      break
    }
  }
  substring_slice(s, start, end)
}

fn expand_tr_set(s : String) -> Array[Char] {
  let result : Array[Char] = []
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < s.length() {
      let escaped = tr_unescape_char(s[i + 1].to_int().unsafe_to_char())
      result.push(escaped)
      i += 2
      continue
    }
    if i + 2 < s.length() &&
      s[i + 1].to_int().unsafe_to_char() == '-' &&
      s[i + 2].to_int().unsafe_to_char() != '\\' {
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

fn tr_unescape_char(ch : Char) -> Char {
  match ch {
    'n' => '\n'
    't' => '\t'
    'r' => '\r'
    '\\' => '\\'
    _ => ch
  }
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
