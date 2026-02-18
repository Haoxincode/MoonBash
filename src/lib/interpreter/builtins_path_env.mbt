// moon_bash Interpreter - Path and Environment Builtins
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

  let mut allow_multiple = false
  let mut suffix : String? = None
  let paths : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-a" {
      allow_multiple = true
      i += 1
      continue
    }
    if arg == "-s" {
      if i + 1 >= args.length() {
        self.stderr_buf.write_string("basename: option requires an argument -- 's'\n")
        self.exit_code = 1
        return
      }
      suffix = Some(args[i + 1])
      allow_multiple = true
      i += 2
      continue
    }
    if arg.has_prefix("-s") && arg.length() > 2 {
      suffix = Some(arg.view(start_offset=2).to_string())
      allow_multiple = true
      i += 1
      continue
    }
    paths.push(arg)
    i += 1
  }

  if paths.length() == 0 {
    self.stderr_buf.write_string("basename: missing operand\n")
    self.exit_code = 1
    return
  }

  if not(allow_multiple) {
    let raw = trim_trailing_slashes_for_path(paths[0])
    let effective_suffix = match suffix {
      Some(s) => Some(s)
      None => {
        if paths.length() > 1 {
          Some(paths[1])
        } else {
          None
        }
      }
    }
    let mut name = @fs.basename(raw)
    match effective_suffix {
      Some(s) => {
        if name.length() > s.length() && name.has_suffix(s) {
          name = name.view(start_offset=0, end_offset=name.length() - s.length()).to_string()
        }
      }
      None => ()
    }
    self.stdout_buf.write_string(name + "\n")
    self.exit_code = 0
    return
  }

  for path in paths {
    let raw = trim_trailing_slashes_for_path(path)
    let mut name = @fs.basename(raw)
    match suffix {
      Some(s) => {
        if name.length() > s.length() && name.has_suffix(s) {
          name = name.view(start_offset=0, end_offset=name.length() - s.length()).to_string()
        }
      }
      None => ()
    }
    self.stdout_buf.write_string(name + "\n")
  }
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

  for path in args {
    let normalized = trim_trailing_slashes_for_path(path)
    if normalized == "/" {
      self.stdout_buf.write_string("/\n")
      continue
    }
    let parent = @fs.parent_path(normalized)
    let result = if parent == "/" && not(normalized.has_prefix("/")) {
      "."
    } else if parent == normalized {
      "."
    } else {
      parent
    }
    self.stdout_buf.write_string(result + "\n")
  }
  self.exit_code = 0
}

fn trim_trailing_slashes_for_path(path : String) -> String {
  if path.length() == 0 {
    return path
  }
  let mut end = path.length()
  while end > 1 && path[end - 1] == '/' {
    end -= 1
  }
  if end == path.length() {
    path
  } else {
    path.view(start_offset=0, end_offset=end).to_string()
  }
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
  let mut first = 1L
  let mut incr = 1L
  let mut last = 1L
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
  if incr == 0L {
    self.stderr_buf.write_string("seq: zero increment\n")
    self.exit_code = 1
    return
  }
  let mut i = first
  let mut count = 0
  while (incr > 0L && i <= last) || (incr < 0L && i >= last) {
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

fn ExecContext::builtin_printenv(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.builtin_env([])
    return
  }
  let mut all_found = true
  for name in args {
    match self.env.get(name) {
      Some(value) => self.stdout_buf.write_string(value + "\n")
      None => all_found = false
    }
  }
  self.exit_code = if all_found { 0 } else { 1 }
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
