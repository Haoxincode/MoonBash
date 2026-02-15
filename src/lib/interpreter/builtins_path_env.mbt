// MoonBash Interpreter - Path and Environment Builtins
// Split from builtins_extra.mbt for maintainability.

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

