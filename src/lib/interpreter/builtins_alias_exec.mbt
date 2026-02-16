// MoonBash Interpreter - Builtins (Alias and Execution)
// alias, unalias, bash, sh, time, sleep, timeout

// Aliases are stored in env vars with "__ALIAS_" prefix.
// e.g. alias ll='ls -l' → env["__ALIAS_ll"] = "ls -l"

let alias_prefix : String = "__ALIAS_"

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
            "moonbash: alias: \{arg}: not found\n",
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
    self.stderr_buf.write_string("moonbash: unalias: usage: unalias [-a] name ...\n")
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
        "moonbash: unalias: \{arg}: not found\n",
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
      self.stderr_buf.write_string("moonbash: -c: option requires an argument\n")
      self.exit_code = 2
      return
    }
    let script = args[1]
    let parsed = try {
      @parser.parse(script)
    } catch {
      @ast.BashError(msg) => {
        self.stderr_buf.write_string("moonbash: \{msg}\n")
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
      self.stderr_buf.write_string("moonbash: \{args[0]}: \{msg}\n")
      self.exit_code = 127
      return
    }
  }
  let parsed = try {
    @parser.parse(content)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moonbash: \{msg}\n")
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
  let cmd_name = args[0]
  let cmd_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }
  self.run_command(cmd_name, cmd_args)
  self.stderr_buf.write_string(
    "\nreal\t0m0.001s\nuser\t0m0.000s\nsys\t0m0.000s\n",
  )
}

fn ExecContext::builtin_sleep(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("moonbash: sleep: missing operand\n")
    self.exit_code = 1
    return
  }
  // Validate the argument looks like a number
  let arg = args[0]
  let mut valid = arg.length() > 0
  let mut has_dot = false
  for i = 0; i < arg.length(); i = i + 1 {
    let ch = arg[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      continue
    } else if ch == '.' && not(has_dot) {
      has_dot = true
    } else {
      valid = false
      break
    }
  }
  if not(valid) {
    self.stderr_buf.write_string(
      "moonbash: sleep: invalid time interval '\{arg}'\n",
    )
    self.exit_code = 1
    return
  }
  // No-op in sandbox — immediate return
  self.exit_code = 0
}

fn ExecContext::builtin_timeout(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() < 2 {
    self.stderr_buf.write_string(
      "moonbash: timeout: missing operand\n",
    )
    self.exit_code = 1
    return
  }
  // First arg is duration (ignored), rest is command
  let cmd_name = args[1]
  let cmd_args : Array[String] = []
  for i = 2; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }
  self.run_command(cmd_name, cmd_args)
}
