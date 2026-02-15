// MoonBash Interpreter - Builtins (State and Flow)
// Split from builtins_core.mbt for maintainability.

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
