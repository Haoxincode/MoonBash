// MoonBash Interpreter - Execution Flow
// Split from interpreter.mbt for maintainability.

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
  let pipelines : Array[@ast.Pipeline] = []
  let ops : Array[Int] = []
  self.flatten_statement(stmt, pipelines, ops)
  if pipelines.length() == 0 {
    return
  }

  self.execute_pipeline(pipelines[0])
  let mut i = 0
  while i < ops.length() {
    if self.should_exit || self.return_requested || self.break_count > 0 ||
      self.continue_count > 0 {
      break
    }
    let should_run = match ops[i] {
      0 => true // ;
      1 => self.exit_code == 0 // &&
      2 => self.exit_code != 0 // ||
      3 => true // &
      _ => false
    }
    if should_run {
      self.execute_pipeline(pipelines[i + 1])
    }
    i += 1
  }
}

/// Flatten right-recursive statement AST into linear pipeline/op lists.
/// op encoding: 0=';', 1='&&', 2='||', 3='&'
fn ExecContext::flatten_statement(
  self : ExecContext,
  stmt : @ast.Statement,
  pipelines : Array[@ast.Pipeline],
  ops : Array[Int]
) -> Unit {
  match stmt {
    @ast.Statement::Pipeline(pipeline) => pipelines.push(pipeline)
    @ast.Statement::AndList(pipeline, next) => {
      pipelines.push(pipeline)
      ops.push(1)
      self.flatten_statement(next, pipelines, ops)
    }
    @ast.Statement::OrList(pipeline, next) => {
      pipelines.push(pipeline)
      ops.push(2)
      self.flatten_statement(next, pipelines, ops)
    }
    @ast.Statement::Sequence(pipeline, next) => {
      pipelines.push(pipeline)
      ops.push(0)
      self.flatten_statement(next, pipelines, ops)
    }
    @ast.Statement::Background(pipeline) => {
      pipelines.push(pipeline)
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
  if cmd.words.length() > 0 {
    let first_parts = self.expand_word(cmd.words[0])
    for part in first_parts {
      expanded.push(part)
    }
    let cmd_name_for_expansion = if expanded.length() > 0 { expanded[0] } else { "" }
    let disable_glob_args = cmd_name_for_expansion == "find"
    let grep_like = is_grep_like_command(cmd_name_for_expansion)
    let mut grep_pattern_set = false
    let mut grep_stop_options = false
    let mut grep_expect_e_pattern = false

    for i = 1; i < cmd.words.length(); i = i + 1 {
      let parts = if disable_glob_args {
        self.expand_word_no_glob(cmd.words[i])
      } else if grep_like {
        let raw_parts = self.expand_word_no_glob(cmd.words[i])
        let expanded_parts : Array[String] = []
        for token in raw_parts {
          let mut no_glob = false
          if grep_expect_e_pattern {
            grep_expect_e_pattern = false
            grep_pattern_set = true
            no_glob = true
          } else if not(grep_stop_options) {
            if token == "--" {
              grep_stop_options = true
              no_glob = true
            } else if token == "-e" || token == "--regexp" {
              grep_expect_e_pattern = true
              no_glob = true
            } else if token.has_prefix("-e") && token.length() > 2 {
              grep_pattern_set = true
              no_glob = true
            } else if token.has_prefix("--regexp=") {
              grep_pattern_set = true
              no_glob = true
            } else if token.length() > 1 && token[0] == '-' {
              no_glob = true
            }
          }
          if not(no_glob) {
            if not(grep_pattern_set) {
              grep_pattern_set = true
              no_glob = true
            }
          }

          if no_glob {
            expanded_parts.push(token)
          } else {
            let globbed = self.pathname_expand([token])
            for piece in globbed {
              expanded_parts.push(piece)
            }
          }
        }
        expanded_parts
      } else {
        self.expand_word(cmd.words[i])
      }
      for part in parts {
        expanded.push(part)
      }
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
      @ast.RedirectOp::HereDoc(_strip_tabs) => {
        let content = self.expand_word_to_string(redir.target)
        self.stdin_buf = content
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

fn is_grep_like_command(cmd_name : String) -> Bool {
  cmd_name == "grep" ||
  cmd_name == "egrep" ||
  cmd_name == "fgrep" ||
  cmd_name == "rg"
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
      @ast.RedirectOp::HereDoc(_strip_tabs) => {
        let content = self.expand_word_to_string(redir.target)
        self.stdin_buf = content
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
