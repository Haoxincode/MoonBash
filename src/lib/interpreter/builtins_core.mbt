// MoonBash Interpreter - Core Builtins
// Split from interpreter.mbt for maintainability.

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
