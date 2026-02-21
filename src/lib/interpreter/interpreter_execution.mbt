// moon_bash Interpreter - Execution Flow
// Split from interpreter.mbt for maintainability.

let alias_runtime_disable_key : String = "__MOON_BASH_ALIAS_EXPANSION_DISABLED"

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
  // Handle assignments
  let has_words = cmd.words.length() > 0

  // Process variable assignments
  if cmd.assignments.length() > 0 {
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
              self.store_array_element_assignment(base, index, value, assign.append)
              continue
            }
            None => ()
          }
          let target_name = self.env.get("__MOON_BASH_NAMEREF__" + assign.name).unwrap_or(
            assign.name,
          )
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
              self.store_array_element_assignment(base, index, "", assign.append)
              continue
            }
            None => ()
          }
          let target_name = self.env.get("__MOON_BASH_NAMEREF__" + assign.name).unwrap_or(
            assign.name,
          )
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
      if not(self.should_exit) && not(keep_expansion_status) {
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
      if self.should_exit {
        return
      }
    }
  }

  if self.should_exit {
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

fn alias_expansion_candidate_name(word : @ast.Word) -> String? {
  if word.parts.length() == 0 {
    return None
  }
  let value = StringBuilder::new()
  for part in word.parts {
    match part {
      @ast.WordPart::Literal(text) => value.write_string(text)
      _ => return None
    }
  }
  let name = value.to_string()
  if name.length() == 0 {
    None
  } else {
    Some(name)
  }
}

fn alias_is_blank_char(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn alias_is_operator_char(ch : Char) -> Bool {
  ch == ';' ||
  ch == '|' ||
  ch == '&' ||
  ch == '(' ||
  ch == ')' ||
  ch == '<' ||
  ch == '>' ||
  ch == '{' ||
  ch == '}'
}

fn alias_first_word_span(source : String) -> (Int, Int, String)? {
  let mut i = 0
  while i < source.length() {
    let ch = source[i].to_int().unsafe_to_char()
    if not(alias_is_blank_char(ch)) {
      break
    }
    i += 1
  }
  if i >= source.length() {
    return None
  }
  let first = source[i].to_int().unsafe_to_char()
  if alias_is_operator_char(first) || first == '\'' || first == '"' {
    return None
  }

  let start = i
  while i < source.length() {
    let ch = source[i].to_int().unsafe_to_char()
    if alias_is_blank_char(ch) || alias_is_operator_char(ch) {
      break
    }
    if ch == '\'' || ch == '"' || ch == '\\' {
      return None
    }
    i += 1
  }
  if i <= start {
    return None
  }

  let word = substring_slice(source, start, i)
  if word.length() == 0 {
    None
  } else {
    Some((start, i, word))
  }
}

fn append_alias_call_args(source : String, args : Array[String]) -> String {
  if args.length() == 0 {
    return source
  }

  let out = StringBuilder::new()
  out.write_string(source)
  if source.length() > 0 {
    let last = source[source.length() - 1].to_int().unsafe_to_char()
    if not(alias_is_blank_char(last)) {
      out.write_char(' ')
    }
  }
  for i = 0; i < args.length(); i = i + 1 {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(printf_shell_quote(args[i]))
  }
  out.to_string()
}

fn ExecContext::resolve_alias_command_source(
  self : ExecContext,
  alias_name : String,
  args : Array[String]
) -> String? {
  let mut source = match self.lookup_alias_value(alias_name) {
    Some(value) => value
    None => return None
  }

  let seen : Map[String, Bool] = {}
  seen[alias_name] = true

  let mut steps = 0
  while steps < 64 {
    steps += 1
    match alias_first_word_span(source) {
      Some((start, end_, first_word)) => {
        if seen.contains(first_word) {
          break
        }
        match self.lookup_alias_value(first_word) {
          Some(next_value) => {
            seen[first_word] = true
            source =
              substring_slice(source, 0, start) +
              next_value +
              substring_slice(source, end_, source.length())
          }
          None => break
        }
      }
      None => break
    }
  }

  Some(append_alias_call_args(source, args))
}

fn ExecContext::try_execute_alias_command(
  self : ExecContext,
  alias_candidate : String?,
  args : Array[String],
  has_multiline_literal_arg : Bool
) -> Bool {
  if not(self.shopt_is_enabled("expand_aliases")) {
    return false
  }
  if self.env.get(alias_runtime_disable_key).unwrap_or("") == "1" {
    return false
  }

  let alias_name = match alias_candidate {
    Some(name) => name
    None => return false
  }

  let source = match self.resolve_alias_command_source(alias_name, args) {
    Some(text) => text
    None => return false
  }

  if has_multiline_literal_arg {
    self.exit_code = 2
    return true
  }

  let parsed = try {
    @parser.parse(source)
  } catch {
    @ast.BashError(_msg) => {
      self.exit_code = 2
      return true
    }
  }

  let saved_disable = self.env.get(alias_runtime_disable_key)
  self.env[alias_runtime_disable_key] = "1"
  self.execute_script(parsed)
  match saved_disable {
    Some(value) => self.env[alias_runtime_disable_key] = value
    None => self.env.remove(alias_runtime_disable_key)
  }
  true
}

fn alias_call_has_multiline_literal_arg(words : Array[@ast.Word]) -> Bool {
  if words.length() <= 1 {
    return false
  }
  for i = 1; i < words.length(); i = i + 1 {
    if word_has_literal_newline(words[i]) {
      return true
    }
  }
  false
}

fn word_has_literal_newline(word : @ast.Word) -> Bool {
  for part in word.parts {
    if word_part_has_literal_newline(part) {
      return true
    }
  }
  false
}

fn word_part_has_literal_newline(part : @ast.WordPart) -> Bool {
  match part {
    @ast.WordPart::Literal(text) => contains_char(text, '\n')
    @ast.WordPart::SingleQuoted(text) => contains_char(text, '\n')
    @ast.WordPart::DoubleQuoted(inner) => {
      for nested in inner {
        if word_part_has_literal_newline(nested) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

fn contains_char(text : String, target : Char) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int().unsafe_to_char() == target {
      return true
    }
  }
  false
}

fn ExecContext::resolve_array_assignment_target(
  self : ExecContext,
  raw_name : String
) -> (String, String)? {
  match parse_array_element_assignment_name(raw_name) {
    Some((base, index_expr)) => {
      let trimmed = trim_ascii_space_simple(index_expr)
      if trimmed.length() == 0 {
        return Some((base, index_expr))
      }

      let expanded_index = self.expand_word_to_string(@parser.parse_word_content(trimmed))
      if self.should_exit {
        return Some((base, index_expr))
      }
      let resolved_index = if expanded_index.length() > 0 { expanded_index } else { trimmed }

      let array_kind_key = "__MOON_BASH_ARRAY_KIND__" + base
      if self.env.get(array_kind_key).unwrap_or("") == "assoc" {
        return Some((base, resolved_index))
      }

      let raw_index = self.eval_arith(@ast.ArithExpr::Raw(resolved_index))
      let count_key = "__MOON_BASH_ARRAY_COUNT__" + base
      let count = parse_int32_str(self.env.get(count_key).unwrap_or("0")).to_int64()
      let final_index = if raw_index < 0L { count + raw_index } else { raw_index }
      if final_index < 0L {
        return Some((base, raw_index.to_string()))
      }
      Some((base, final_index.to_string()))
    }
    None => None
  }
}

fn word_has_status_sensitive_expansion(word : @ast.Word) -> Bool {
  for part in word.parts {
    if word_part_has_status_sensitive_expansion(part) {
      return true
    }
  }
  false
}

fn word_part_has_status_sensitive_expansion(part : @ast.WordPart) -> Bool {
  match part {
    @ast.WordPart::CommandSubstitution(_) => true
    @ast.WordPart::ArithmeticExpansion(_) => true
    @ast.WordPart::DoubleQuoted(inner) => {
      for nested in inner {
        if word_part_has_status_sensitive_expansion(nested) {
          return true
        }
      }
      false
    }
    @ast.WordPart::BraceExpansion(options) => {
      for option in options {
        for nested in option {
          if word_part_has_status_sensitive_expansion(nested) {
            return true
          }
        }
      }
      false
    }
    @ast.WordPart::ParameterExpansion(expansion) =>
      param_expansion_has_status_sensitive_expansion(expansion)
    _ => false
  }
}

fn param_expansion_has_status_sensitive_expansion(
  expansion : @ast.ParamExpansion
) -> Bool {
  match expansion {
    @ast.ParamExpansion::Default(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::Assign(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::Error(_, maybe_word, _) =>
      match maybe_word {
        Some(word) => word_has_status_sensitive_expansion(word)
        None => false
      }
    @ast.ParamExpansion::Alternative(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::PrefixRemove(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::SuffixRemove(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::Replace(_, pattern, maybe_repl, _) => {
      if word_has_status_sensitive_expansion(pattern) {
        return true
      }
      match maybe_repl {
        Some(repl) => word_has_status_sensitive_expansion(repl)
        None => false
      }
    }
    @ast.ParamExpansion::Uppercase(_, maybe_pattern, _) =>
      match maybe_pattern {
        Some(pattern) => word_has_status_sensitive_expansion(pattern)
        None => false
      }
    @ast.ParamExpansion::Lowercase(_, maybe_pattern, _) =>
      match maybe_pattern {
        Some(pattern) => word_has_status_sensitive_expansion(pattern)
        None => false
      }
    _ => false
  }
}

fn is_grep_like_command(cmd_name : String) -> Bool {
  cmd_name == "grep" ||
  cmd_name == "egrep" ||
  cmd_name == "fgrep" ||
  cmd_name == "rg"
}

fn ExecContext::store_scalar_assignment(
  self : ExecContext,
  name : String,
  value : String
) -> Bool {
  self.store_scalar_assignment_with_options(name, value, true)
}

fn ExecContext::store_scalar_assignment_with_options(
  self : ExecContext,
  name : String,
  value : String,
  enforce_readonly : Bool
) -> Bool {
  if enforce_readonly && self.is_readonly_variable(name) {
    self.stderr_buf.write_string("moon_bash: \{name}: readonly variable\n")
    self.exit_code = 1
    return false
  }
  let final_value = self.apply_variable_attributes(name, value)
  if final_value.length() > self.limits.max_string_length {
    self.fail_execution_limit("string length limit exceeded")
    return false
  }
  self.env[name] = final_value
  true
}
