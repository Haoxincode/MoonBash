// moon_bash Interpreter - Builtins (I/O and Meta)
// Split from builtins_core.mbt for maintainability.

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
  let mut array_name : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == "-p" && i + 1 < args.length() {
      prompt = args[i + 1]
      i += 2
    } else if args[i] == "-a" && i + 1 < args.length() {
      array_name = Some(args[i + 1])
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

  // Split line by current IFS and assign.
  let words = self.word_split(line)
  match array_name {
    Some(name) => self.store_array_assignment(name, words)
    None => {
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

fn ExecContext::builtin_mapfile(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut strip_newline = false
  let mut array_name = "MAPFILE"
  let mut i = 0

  while i < args.length() {
    let arg = args[i]
    if arg == "-t" {
      strip_newline = true
      i += 1
      continue
    }
    if arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      // Ignore unsupported flags for now.
      i += 1
      continue
    }
    array_name = arg
    i += 1
  }

  let lines = mapfile_split_lines(self.stdin_buf, strip_newline)
  if lines.length() > self.limits.max_array_elements {
    self.stderr_buf.write_string("mapfile: array element limit exceeded\n")
    self.exit_code = 1
    return
  }

  // Remove previous values for this array name.
  let remove_keys : Array[String] = []
  let index_prefix = array_name + "["
  let count_key = array_count_storage_key(array_name)
  for key, _value in self.env {
    if key == count_key || mapfile_starts_with(key, index_prefix) {
      remove_keys.push(key)
    }
  }
  for key in remove_keys {
    self.env.remove(key)
  }

  let joined = StringBuilder::new()
  for idx = 0; idx < lines.length(); idx = idx + 1 {
    let value = lines[idx]
    self.env["\{array_name}[\{idx.to_string()}]"] = value
    if idx > 0 {
      joined.write_char(' ')
    }
    joined.write_string(value)
  }
  self.env[array_name + "[@]"] = joined.to_string()
  self.env[array_name + "[*]"] = joined.to_string()
  self.env[count_key] = lines.length().to_string()
  self.exit_code = 0
}

fn mapfile_split_lines(input : String, strip_newline : Bool) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      let line = if strip_newline { buf.to_string() } else { buf.to_string() + "\n" }
      lines.push(line)
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    lines.push(remaining)
  }
  lines
}

fn mapfile_starts_with(s : String, prefix : String) -> Bool {
  if prefix.length() > s.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

fn array_count_storage_key(name : String) -> String {
  "__MOON_BASH_ARRAY_COUNT__" + name
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

fn ExecContext::builtin_double_bracket(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // Mirror [[ ... ]] minimal semantics through the same evaluator.
  let test_args = if args.length() > 0 && args[args.length() - 1] == "]]" {
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
      self.stderr_buf.write_string("moon_bash: eval: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
}

fn ExecContext::builtin_let(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 1
    return
  }

  let mut last = 0L
  for expr_text in args {
    last = self.eval_arith(@ast.ArithExpr::Raw(expr_text))
  }
  self.exit_code = if last != 0L { 0 } else { 1 }
}

fn ExecContext::builtin_source(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("moon_bash: source: filename argument required\n")
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
      self.stderr_buf.write_string("moon_bash: source: \{msg}\n")
      self.exit_code = 1
      return
    }
  }
  let parsed = try {
    @parser.parse(content)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moon_bash: source: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
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
            "moon_bash: type: \{arg}: not found\n",
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
      self.stderr_buf.write_string("moon_bash: \{cmd_name}: command not found\n")
      self.exit_code = 127
    }
  }
}
