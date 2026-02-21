// moon_bash Interpreter - Execution Flow
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
  let first_next_op = if ops.length() > 0 { Some(ops[0]) } else { None }
  self.apply_errexit_after_pipeline(pipelines[0], first_next_op)
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
      let pipeline_idx = i + 1
      self.execute_pipeline(pipelines[pipeline_idx])
      let next_op = if pipeline_idx < ops.length() {
        Some(ops[pipeline_idx])
      } else {
        None
      }
      self.apply_errexit_after_pipeline(pipelines[pipeline_idx], next_op)
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

  let pipeline_statuses : Array[String] = []
  if commands.length() == 1 {
    // Single command, no piping needed
    self.execute_command(commands[0])
    pipeline_statuses.push(self.exit_code.to_string())
  } else {
    // Multi-command pipeline: chain stdout -> stdin.
    // Each stage runs in an isolated scope (like a subshell).
    let saved_stdin = self.stdin_buf
    let saved_stdout = self.stdout_buf

    let mut pipe_input = self.stdin_buf
    for i = 0; i < commands.length(); i = i + 1 {
      let stage_env : Map[String, String] = {}
      for key, value in self.env {
        stage_env[key] = value
      }
      let stage_exported : Map[String, Bool] = {}
      for key, value in self.exported {
        stage_exported[key] = value
      }
      let stage_functions : Map[String, @ast.FunctionDef] = {}
      for key, value in self.functions {
        stage_functions[key] = value
      }
      let stage_cwd = self.cwd
      let stage_should_exit = self.should_exit
      let stage_return_requested = self.return_requested
      let stage_break_count = self.break_count
      let stage_continue_count = self.continue_count

      self.should_exit = false
      self.return_requested = false
      self.break_count = 0
      self.continue_count = 0
      self.stdin_buf = pipe_input
      self.stdout_buf = StringBuilder::new()
      self.execute_command(commands[i])
      pipeline_statuses.push(self.exit_code.to_string())
      pipe_input = self.stdout_buf.to_string()

      self.env = stage_env
      self.exported = stage_exported
      self.functions = stage_functions
      self.cwd = stage_cwd
      self.should_exit = stage_should_exit
      self.return_requested = stage_return_requested
      self.break_count = stage_break_count
      self.continue_count = stage_continue_count
    }

    // Write final command output to the original stdout
    saved_stdout.write_string(pipe_input)
    self.stdout_buf = saved_stdout
    self.stdin_buf = saved_stdin
    let mut pipeline_exit = parse_int32_str(pipeline_statuses[pipeline_statuses.length() - 1])
    if self.options.pipefail {
      pipeline_exit = 0
      for status in pipeline_statuses {
        let code = parse_int32_str(status)
        if code != 0 {
          pipeline_exit = code
        }
      }
    }
    self.exit_code = pipeline_exit
    self.enforce_output_size_limit()
  }

  self.store_array_assignment("PIPESTATUS", pipeline_statuses)

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
    self.fail_execution_limit("too many commands executed")
    return
  }

  match cmd {
    @ast.Command::Simple(simple) => self.execute_simple(simple)
    @ast.Command::Compound(compound, redirs) => {
      let saved_stdout = self.stdout_buf
      let saved_stderr = self.stderr_buf
      let saved_stdin = self.stdin_buf
      let mut redirected_file : String? = None
      let mut redirect_append = false
      let mut null_output = false
      let mut stdout_to_stderr = false
      let mut stderr_to_stdout = false
      let mut input_from_file = false

      for redir in redirs {
        match redir.op {
          @ast.RedirectOp::Output => {
            let target = self.expand_word_to_string(redir.target)
            if target == "/dev/null" {
              null_output = true
              self.stdout_buf = StringBuilder::new()
            } else if target == "/dev/stderr" {
              stdout_to_stderr = true
              self.stdout_buf = StringBuilder::new()
            } else if target != "/dev/stdout" {
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
            } else if target != "/dev/stdout" && target != "/dev/stderr" {
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
                self.stderr_buf.write_string("moon_bash: \{msg}\n")
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
          @ast.RedirectOp::DupOutput => {
            let target = self.expand_word_to_string(redir.target)
            let source_fd = match redir.fd {
              Some(fd) => fd
              None => 1
            }
            if source_fd == 1 && (target == "2" || target == "/dev/stderr") {
              stdout_to_stderr = true
              self.stdout_buf = StringBuilder::new()
            } else if source_fd == 2 && (target == "1" || target == "/dev/stdout") {
              stderr_to_stdout = true
              self.stderr_buf = StringBuilder::new()
            } else if source_fd == 1 && target == "-" {
              null_output = true
              self.stdout_buf = StringBuilder::new()
            }
          }
          _ => ()
        }
      }

      self.execute_compound(compound)

      match redirected_file {
        Some(path) => {
          let mut output = self.stdout_buf.to_string()
          if stderr_to_stdout {
            output = output + self.stderr_buf.to_string()
          }
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
              saved_stderr.write_string("moon_bash: \{msg}\n")
          }
          self.stdout_buf = saved_stdout
          if stderr_to_stdout {
            self.stderr_buf = saved_stderr
          }
        }
        None => {
          if stdout_to_stderr {
            let output = self.stdout_buf.to_string()
            saved_stderr.write_string(output)
            self.stdout_buf = saved_stdout
          } else if null_output {
            self.stdout_buf = saved_stdout
          }
          if stderr_to_stdout {
            let output = self.stderr_buf.to_string()
            saved_stdout.write_string(output)
            self.stderr_buf = saved_stderr
          }
        }
      }

      if input_from_file {
        self.stdin_buf = saved_stdin
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
  self.env.remove("__MOON_BASH_ABORT_CURRENT_COMMAND__")

  // Handle assignments
  let has_words = cmd.words.length() > 0
  let mut prefix_assignment_restore_names : Array[String] = []
  let mut prefix_assignment_snapshot : Map[String, String] = {}
  let mut track_prefix_assignment_restore = false

  // Process variable assignments
  if cmd.assignments.length() > 0 {
    // Assignment command status is independent from previous pipeline status.
    self.exit_code = 0
    if has_words {
      prefix_assignment_restore_names = collect_assignment_restore_names(cmd.assignments)
      if prefix_assignment_restore_names.length() > 0 {
        prefix_assignment_snapshot = snapshot_assignment_env_entries(
          self.env,
          prefix_assignment_restore_names,
        )
        track_prefix_assignment_restore = true
      }
    }
    let mut keep_expansion_status = false
    for assign in cmd.assignments {
      match assign.value {
        Some(word) => {
          if word_has_status_sensitive_expansion(word) {
            keep_expansion_status = true
          }
          if self.try_store_array_assignment(assign.name, word, assign.append) {
            continue
          }
          let value = self.expand_word_to_string(word)
          if self.should_exit {
            return
          }
          match self.resolve_array_assignment_target(assign.name) {
            Some((base, index)) => {
              if self.should_exit {
                return
              }
              match split_array_assignment_items(word.parts) {
                Some(_) => {
                  self.exit_code = 2
                  self.should_exit = true
                  return
                }
                None => ()
              }
              self.store_array_element_assignment(base, index, value, assign.append)
              continue
            }
            None => ()
          }
          let target_name = self.env.get("__MOON_BASH_NAMEREF__" + assign.name).unwrap_or(
            assign.name,
          )
          match self.resolve_array_assignment_target(target_name) {
            Some((target_base, target_index)) => {
              if self.should_exit {
                return
              }
              self.store_array_element_assignment(
                target_base,
                target_index,
                value,
                assign.append,
              )
              if self.should_exit {
                return
              }
              continue
            }
            None => ()
          }
          if assign.append {
            if self.append_scalar_array_assignment(target_name, value) {
              if self.should_exit {
                return
              }
              continue
            }
          }
          let next_value = if assign.append {
            let existing = self.env.get(target_name).unwrap_or("")
            existing + value
          } else {
            value
          }
          if not(self.store_scalar_assignment(target_name, next_value)) {
            return
          }
        }
        None => {
          match self.resolve_array_assignment_target(assign.name) {
            Some((base, index)) => {
              if self.should_exit {
                return
              }
              self.store_array_element_assignment(base, index, "", assign.append)
              continue
            }
            None => ()
          }
          let target_name = self.env.get("__MOON_BASH_NAMEREF__" + assign.name).unwrap_or(
            assign.name,
          )
          match self.resolve_array_assignment_target(target_name) {
            Some((target_base, target_index)) => {
              if self.should_exit {
                return
              }
              self.store_array_element_assignment(
                target_base,
                target_index,
                "",
                assign.append,
              )
              if self.should_exit {
                return
              }
              continue
            }
            None => ()
          }
          if assign.append {
            if self.append_scalar_array_assignment(target_name, "") {
              if self.should_exit {
                return
              }
              continue
            }
          }
          let next_value = if assign.append {
            self.env.get(target_name).unwrap_or("")
          } else {
            ""
          }
          if not(self.store_scalar_assignment(target_name, next_value)) {
            return
          }
        }
      }
    }
    // If no words follow, we're done (assignment-only command)
    if not(has_words) {
      if not(self.should_exit) && not(keep_expansion_status) && self.exit_code == 0 {
        self.exit_code = 0
      }
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
    if self.should_exit {
      return
    }
    let cmd_name_for_expansion = if expanded.length() > 0 { expanded[0] } else { "" }
    let assignment_builtin = is_assignment_builtin_name(cmd_name_for_expansion)
    let conditional_test = cmd_name_for_expansion == "[["
    let disable_glob_args = cmd_name_for_expansion == "find"
    let grep_like = is_grep_like_command(cmd_name_for_expansion)
    let mut grep_pattern_set = false
    let mut grep_stop_options = false
    let mut grep_expect_e_pattern = false

    for i = 1; i < cmd.words.length(); i = i + 1 {
      let parts = if assignment_builtin {
        match self.expand_compound_assignment_argument(cmd.words[i]) {
          Some(raw) => [raw]
          None => self.expand_word(cmd.words[i])
        }
      } else if conditional_test {
        [self.expand_word_to_string(cmd.words[i])]
      } else if disable_glob_args {
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
      if self.should_exit {
        return
      }
    }
  }

  if self.should_exit {
    return
  }

  if self.env.contains("__MOON_BASH_ABORT_CURRENT_COMMAND__") {
    self.env.remove("__MOON_BASH_ABORT_CURRENT_COMMAND__")
    return
  }

  if expanded.length() == 0 {
    self.exit_code = 0
    return
  }

  let alias_candidate = if cmd.words.length() > 0 {
    alias_expansion_candidate_name(cmd.words[0])
  } else {
    None
  }
  let alias_has_multiline_literal_arg = alias_call_has_multiline_literal_arg(cmd.words)

  let cmd_name = expanded[0]
  let args : Array[String] = []
  for i = 1; i < expanded.length(); i = i + 1 {
    args.push(expanded[i])
  }
  let should_restore_prefix_assignments = track_prefix_assignment_restore &&
    not(command_keeps_prefix_assignments(cmd_name))

  // Apply redirections
  let saved_stdout = self.stdout_buf
  let saved_stderr = self.stderr_buf
  let saved_stdin = self.stdin_buf
  let mut redirected_file : String? = None
  let mut redirect_append = false
  let mut redirected_stderr_file : String? = None
  let mut redirect_stderr_append = false
  let mut null_output = false
  let mut null_stderr = false
  let mut stdout_to_stderr = false
  let mut stderr_to_stdout = false
  let mut input_from_file = false
  let exec_builtin = cmd_name == "exec"

  for redir in cmd.redirections {
    match redir.op {
      @ast.RedirectOp::Output => {
        let target = self.expand_word_to_string(redir.target)
        let source_fd = match redir.fd {
          Some(fd) => fd
          None => 1
        }
        if exec_builtin && source_fd != 1 {
          self.store_fd_output_mapping(source_fd, target, false)
          continue
        }
        if source_fd == 2 {
          if target == "/dev/null" {
            null_stderr = true
            self.stderr_buf = StringBuilder::new()
          } else if target == "/dev/stdout" || target == "1" {
            stderr_to_stdout = true
            self.stderr_buf = StringBuilder::new()
          } else {
            redirected_stderr_file = Some(target)
            redirect_stderr_append = false
            self.stderr_buf = StringBuilder::new()
          }
          continue
        }
        if source_fd != 1 {
          continue
        }
        if target == "/dev/null" {
          null_output = true
          self.stdout_buf = StringBuilder::new()
        } else if target == "/dev/stderr" {
          stdout_to_stderr = true
          self.stdout_buf = StringBuilder::new()
        } else {
          redirected_file = Some(target)
          redirect_append = false
          self.stdout_buf = StringBuilder::new()
        }
      }
      @ast.RedirectOp::Append => {
        let target = self.expand_word_to_string(redir.target)
        let source_fd = match redir.fd {
          Some(fd) => fd
          None => 1
        }
        if exec_builtin && source_fd != 1 {
          self.store_fd_output_mapping(source_fd, target, true)
          continue
        }
        if source_fd == 2 {
          if target == "/dev/null" {
            null_stderr = true
            self.stderr_buf = StringBuilder::new()
          } else if target == "/dev/stdout" || target == "1" {
            stderr_to_stdout = true
            self.stderr_buf = StringBuilder::new()
          } else {
            redirected_stderr_file = Some(target)
            redirect_stderr_append = true
            self.stderr_buf = StringBuilder::new()
          }
          continue
        }
        if source_fd != 1 {
          continue
        }
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
        if target == "/dev/null" {
          self.stdin_buf = ""
          input_from_file = true
          continue
        }
        let resolved = try {
          @fs.resolve_path(self.cwd, target)
        } catch {
          _ => target
        }
        let content = try {
          self.fs.read_file(resolved)
        } catch {
          @fs.FsError(msg) => {
            self.stderr_buf.write_string("moon_bash: \{msg}\n")
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
      @ast.RedirectOp::DupOutput => {
        let target = self.expand_word_to_string(redir.target)
        let source_fd = match redir.fd {
          Some(fd) => fd
          None => 1
        }
        if exec_builtin {
          if target == "-" {
            self.env.remove(fd_output_key(source_fd))
            continue
          }
          match parse_fd_target_number(target) {
            Some(target_fd) => {
              match self.env.get(fd_output_key(target_fd)) {
                Some(spec) => self.env[fd_output_key(source_fd)] = spec
                None => self.env.remove(fd_output_key(source_fd))
              }
              continue
            }
            None => ()
          }
        }
        if source_fd == 1 {
          match self.load_fd_output_mapping(target) {
            Some((path, append_mode)) => {
              if path == "/dev/null" {
                null_output = true
                self.stdout_buf = StringBuilder::new()
              } else if path == "/dev/stderr" {
                stdout_to_stderr = true
                self.stdout_buf = StringBuilder::new()
              } else {
                redirected_file = Some(path)
                redirect_append = append_mode
                self.stdout_buf = StringBuilder::new()
              }
              continue
            }
            None => ()
          }
        }
        if source_fd == 2 && (target == "1" || target == "/dev/stdout") {
          stderr_to_stdout = true
          self.stderr_buf = StringBuilder::new()
        } else if source_fd == 2 && target == "-" {
          null_stderr = true
          self.stderr_buf = StringBuilder::new()
        }
        if source_fd == 1 && (target == "2" || target == "/dev/stderr") {
          stdout_to_stderr = true
          self.stdout_buf = StringBuilder::new()
        } else if source_fd == 1 && target == "-" {
          null_output = true
          self.stdout_buf = StringBuilder::new()
        }
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
  if not(
    self.try_execute_alias_command(
      alias_candidate,
      args,
      alias_has_multiline_literal_arg,
    )
  ) {
    self.run_command(cmd_name, args)
  }
  if should_restore_prefix_assignments {
    restore_assignment_env_entries(
      self.env,
      prefix_assignment_restore_names,
      prefix_assignment_snapshot,
    )
  }

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
          self.stderr_buf.write_string("moon_bash: \{msg}\n")
      }
      self.stdout_buf = saved_stdout
    }
    None => {
      if stdout_to_stderr {
        let output = self.stdout_buf.to_string()
        saved_stderr.write_string(output)
        self.stdout_buf = saved_stdout
      } else if null_output {
        self.stdout_buf = saved_stdout
      }
    }
  }

  match redirected_stderr_file {
    Some(path) => {
      let output = self.stderr_buf.to_string()
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        if redirect_stderr_append {
          self.fs.append_file(resolved, output)
        } else {
          self.fs.write_file(resolved, output)
        }
      } catch {
        @fs.FsError(msg) =>
          saved_stderr.write_string("moon_bash: \{msg}\n")
      }
      self.stderr_buf = saved_stderr
    }
    None => {
      if stderr_to_stdout {
        let output = self.stderr_buf.to_string()
        saved_stdout.write_string(output)
        self.stderr_buf = saved_stderr
      } else if null_stderr {
        self.stderr_buf = saved_stderr
      }
    }
  }

  if input_from_file {
    self.stdin_buf = saved_stdin
  }
  self.enforce_output_size_limit()
}

fn is_assignment_builtin_name(cmd_name : String) -> Bool {
  cmd_name == "declare" ||
  cmd_name == "typeset" ||
  cmd_name == "local" ||
  cmd_name == "readonly"
}

fn ExecContext::append_scalar_array_assignment(
  self : ExecContext,
  name : String,
  suffix : String
) -> Bool {
  if not(self.env.contains(test_array_count_storage_key(name))) {
    return false
  }

  let kind = self.env.get(test_array_kind_storage_key(name)).unwrap_or("indexed")
  if kind == "assoc" {
    self.exit_code = 1
    self.should_exit = true
    return true
  }

  let element_key = "\{name}[0]"
  self.env[element_key] = self.env.get(element_key).unwrap_or("") + suffix
  self.refresh_array_metadata(name)
  true
}

fn ExecContext::expand_compound_assignment_argument(
  self : ExecContext,
  word : @ast.Word
) -> String? {
  let raw = self.expand_word_to_string(word)
  if self.should_exit {
    return None
  }

  match parse_name_value_spec(raw) {
    Some((_name, Some(raw_value), _append)) => {
      let parsed = @parser.parse_word_content(raw_value)
      match split_array_assignment_items(parsed.parts) {
        Some(_) => Some(raw)
        None => None
      }
    }
    _ => None
  }
}
