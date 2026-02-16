// moon_bash Interpreter - Builtins (Alias and Execution)
// alias, unalias, bash, sh, time, sleep, timeout

// Aliases are stored in env vars with "__ALIAS_" prefix.
// e.g. alias ll='ls -l' → env["__ALIAS_ll"] = "ls -l"

let alias_prefix : String = "__ALIAS_"

fn shell_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn shell_parse_duration_ms(raw : String) -> Result[Int, String] {
  if raw.length() == 0 {
    return Err("invalid time interval '\{raw}'")
  }
  let mut unit_ms = 1000
  let mut end_ = raw.length()
  if raw.length() >= 2 && raw[raw.length() - 2].to_int().unsafe_to_char() == 'm' && raw[raw.length() - 1].to_int().unsafe_to_char() == 's' {
    unit_ms = 1
    end_ = raw.length() - 2
  } else {
    let suffix = raw[raw.length() - 1].to_int().unsafe_to_char()
    match suffix {
      's' => {
        unit_ms = 1000
        end_ = raw.length() - 1
      }
      'm' => {
        unit_ms = 60 * 1000
        end_ = raw.length() - 1
      }
      'h' => {
        unit_ms = 60 * 60 * 1000
        end_ = raw.length() - 1
      }
      'd' => {
        unit_ms = 24 * 60 * 60 * 1000
        end_ = raw.length() - 1
      }
      _ => ()
    }
  }
  if end_ <= 0 {
    return Err("invalid time interval '\{raw}'")
  }
  let mut start = 0
  if raw[0].to_int().unsafe_to_char() == '+' {
    start = 1
  } else if raw[0].to_int().unsafe_to_char() == '-' {
    return Err("invalid time interval '\{raw}'")
  }
  if start >= end_ {
    return Err("invalid time interval '\{raw}'")
  }
  let mut whole = 0
  let mut frac = 0
  let mut frac_scale = 1
  let mut has_digit = false
  let mut seen_dot = false
  for i = start; i < end_; i = i + 1 {
    let ch = raw[i].to_int().unsafe_to_char()
    if shell_is_digit(ch) {
      has_digit = true
      let digit = ch.to_int() - '0'.to_int()
      if seen_dot {
        if frac_scale < 1000000 {
          frac = frac * 10 + digit
          frac_scale = frac_scale * 10
        }
      } else {
        whole = whole * 10 + digit
      }
    } else if ch == '.' && not(seen_dot) {
      seen_dot = true
    } else {
      return Err("invalid time interval '\{raw}'")
    }
  }
  if not(has_digit) {
    return Err("invalid time interval '\{raw}'")
  }
  let max_ms = 2147483647
  if whole > max_ms / unit_ms {
    return Err("invalid time interval '\{raw}'")
  }
  let mut total = whole * unit_ms
  if frac > 0 {
    let frac_ms = (frac * unit_ms) / frac_scale
    if frac_ms > max_ms - total {
      return Err("invalid time interval '\{raw}'")
    }
    total += frac_ms
  }
  Ok(total)
}

fn shell_parse_total_duration_ms(args : Array[String]) -> Result[Int, String] {
  let mut total = 0
  for raw in args {
    let duration_ms = match shell_parse_duration_ms(raw) {
      Ok(value) => value
      Err(msg) => return Err(msg)
    }
    if duration_ms > 2147483647 - total {
      return Err("invalid time interval '\{raw}'")
    }
    total += duration_ms
  }
  Ok(total)
}

fn shell_pad3(value : Int) -> String {
  if value < 10 {
    "00" + value.to_string()
  } else if value < 100 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

fn ExecContext::builtin_alias(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    // List all aliases
    for k, v in self.env {
      if k.has_prefix(alias_prefix) {
        let name = k.substring(start=alias_prefix.length())
        self.stdout_buf.write_string("alias \{name}='\{v}'\n")
      }
    }
    self.exit_code = 0
    return
  }
  for arg in args {
    // Find '=' to distinguish set vs show
    let mut eq_pos = -1
    for i = 0; i < arg.length(); i = i + 1 {
      if arg[i] == '=' {
        eq_pos = i
        break
      }
    }
    if eq_pos > 0 {
      // name=value → set alias
      let name = arg.substring(start=0, end=eq_pos)
      let value = arg.substring(start=eq_pos + 1)
      self.env[alias_prefix + name] = value
    } else {
      // name only → show alias
      let key = alias_prefix + arg
      match self.env.get(key) {
        Some(v) =>
          self.stdout_buf.write_string("alias \{arg}='\{v}'\n")
        None => {
          self.stderr_buf.write_string(
            "moon_bash: alias: \{arg}: not found\n",
          )
          self.exit_code = 1
          return
        }
      }
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_unalias(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("moon_bash: unalias: usage: unalias [-a] name ...\n")
    self.exit_code = 2
    return
  }
  if args[0] == "-a" {
    // Remove all aliases
    let to_remove : Array[String] = []
    for k, _v in self.env {
      if k.has_prefix(alias_prefix) {
        to_remove.push(k)
      }
    }
    for k in to_remove {
      self.env.remove(k)
    }
    self.exit_code = 0
    return
  }
  for arg in args {
    let key = alias_prefix + arg
    if self.env.contains(key) {
      self.env.remove(key)
    } else {
      self.stderr_buf.write_string(
        "moon_bash: unalias: \{arg}: not found\n",
      )
      self.exit_code = 1
      return
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_bash(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    // No args: interactive mode not supported
    self.exit_code = 0
    return
  }
  if args[0] == "-c" {
    // bash -c 'script'
    if args.length() < 2 {
      self.stderr_buf.write_string("moon_bash: -c: option requires an argument\n")
      self.exit_code = 2
      return
    }
    let script = args[1]
    let parsed = try {
      @parser.parse(script)
    } catch {
      @ast.BashError(msg) => {
        self.stderr_buf.write_string("moon_bash: \{msg}\n")
        self.exit_code = 2
        return
      }
    }
    self.execute_script(parsed)
    return
  }
  // Otherwise treat first arg as a script file
  let path = try {
    @fs.resolve_path(self.cwd, args[0])
  } catch {
    _ => args[0]
  }
  let content = try {
    self.fs.read_file(path)
  } catch {
    @fs.FsError(msg) => {
      self.stderr_buf.write_string("moon_bash: \{args[0]}: \{msg}\n")
      self.exit_code = 127
      return
    }
  }
  let parsed = try {
    @parser.parse(content)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moon_bash: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
}

fn ExecContext::builtin_sh(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  self.builtin_bash(args)
}

fn ExecContext::builtin_time(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 0
    return
  }
  let start_ms = @ffi.now_ms_sync()
  let cmd_name = args[0]
  let cmd_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }
  self.run_command(cmd_name, cmd_args)
  let end_ms = @ffi.now_ms_sync()
  let elapsed_ms = if end_ms >= start_ms { end_ms - start_ms } else { 0 }
  let minutes = elapsed_ms / 60000
  let seconds = (elapsed_ms % 60000) / 1000
  let millis = elapsed_ms % 1000
  self.stderr_buf.write_string(
    "\nreal\t\{minutes}m\{seconds}.\{shell_pad3(millis)}s\n",
  )
  self.stderr_buf.write_string("user\t0m0.000s\nsys\t0m0.000s\n")
}

fn ExecContext::builtin_sleep(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("moon_bash: sleep: missing operand\n")
    self.exit_code = 1
    return
  }
  let duration_ms = match shell_parse_total_duration_ms(args) {
    Ok(value) => value
    Err(msg) => {
      self.stderr_buf.write_string("moon_bash: sleep: \{msg}\n")
      self.exit_code = 1
      return
    }
  }
  let sleep_error = @ffi.sleep_sync(duration_ms)
  if sleep_error.length() > 0 {
    self.stderr_buf.write_string(
      "moon_bash: sleep: \{sleep_error}\n",
    )
    self.exit_code = 1
    return
  }
  self.exit_code = 0
}

fn ExecContext::builtin_timeout(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() < 2 {
    self.stderr_buf.write_string(
      "moon_bash: timeout: missing operand\n",
    )
    self.exit_code = 1
    return
  }
  let duration_ms = match shell_parse_duration_ms(args[0]) {
    Ok(value) => value
    Err(msg) => {
      self.stderr_buf.write_string("moon_bash: timeout: \{msg}\n")
      self.exit_code = 1
      return
    }
  }
  let cmd_name = args[1]
  let cmd_args : Array[String] = []
  for i = 2; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }
  let start_ms = @ffi.now_ms_sync()
  self.run_command(cmd_name, cmd_args)
  let end_ms = @ffi.now_ms_sync()
  let elapsed_ms = if end_ms >= start_ms { end_ms - start_ms } else { 0 }
  if elapsed_ms > duration_ms {
    self.stderr_buf.write_string(
      "moon_bash: timeout: command timed out after \{args[0]}\n",
    )
    self.exit_code = 124
  }
}
