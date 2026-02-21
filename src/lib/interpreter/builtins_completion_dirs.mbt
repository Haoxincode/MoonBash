// moon_bash Interpreter - Directory Stack Builtins (dirs, pushd, popd)

fn ExecContext::get_directory_stack(self : ExecContext) -> Array[String] {
  let stack : Array[String] = []
  let raw = self.env.get(dir_stack_storage_key).unwrap_or("")
  if raw.length() > 0 {
    let parts = split_string_by_delimiter(raw, "\n")
    for path in parts {
      if path.length() > 0 {
        stack.push(path)
      }
    }
  }
  if stack.length() == 0 {
    stack.push(self.cwd)
  }
  stack
}

fn ExecContext::set_directory_stack(
  self : ExecContext,
  stack_input : Array[String]
) -> Unit {
  let stack : Array[String] = []
  for path in stack_input {
    stack.push(path)
  }
  if stack.length() == 0 {
    stack.push(self.cwd)
  }

  let buf = StringBuilder::new()
  for i = 0; i < stack.length(); i = i + 1 {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(stack[i])
  }
  self.env[dir_stack_storage_key] = buf.to_string()
}

fn ExecContext::sync_directory_stack_with_cwd(self : ExecContext) -> Unit {
  let stack = self.get_directory_stack()
  if stack.length() == 0 {
    self.set_directory_stack([self.cwd])
    return
  }
  stack[0] = self.cwd
  self.set_directory_stack(stack)
}

fn ExecContext::render_directory_stack(
  self : ExecContext,
  stack : Array[String],
  long_format : Bool,
  one_per_line : Bool,
  numbered : Bool
) -> Unit {
  let home = self.env.get("HOME").unwrap_or("")
  if numbered {
    for i = 0; i < stack.length(); i = i + 1 {
      let shown = if long_format {
        stack[i]
      } else {
        completion_tilde_path(stack[i], home)
      }
      self.stdout_buf.write_string(" \{i.to_string()}  \{shown}\n")
    }
    return
  }

  if one_per_line {
    for path in stack {
      let shown = if long_format {
        path
      } else {
        completion_tilde_path(path, home)
      }
      self.stdout_buf.write_string(shown + "\n")
    }
    return
  }

  let buf = StringBuilder::new()
  for i = 0; i < stack.length(); i = i + 1 {
    if i > 0 {
      buf.write_char(' ')
    }
    let shown = if long_format {
      stack[i]
    } else {
      completion_tilde_path(stack[i], home)
    }
    buf.write_string(shown)
  }
  self.stdout_buf.write_string(buf.to_string() + "\n")
}

fn ExecContext::builtin_dirs(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  self.sync_directory_stack_with_cwd()
  let mut long_format = false
  let mut one_per_line = false
  let mut numbered = false
  let mut clear_stack = false

  let mut i = 0
  let mut parse_flags = true
  while i < args.length() {
    let arg = args[i]
    if parse_flags && arg == "--" {
      parse_flags = false
      i += 1
      continue
    }
    if parse_flags && arg.length() > 1 && arg[0].to_int().unsafe_to_char() == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let ch = arg[j].to_int().unsafe_to_char()
        match ch {
          'c' => clear_stack = true
          'l' => long_format = true
          'p' => one_per_line = true
          'v' => numbered = true
          _ => {
            self.exit_code = 2
            return
          }
        }
      }
      i += 1
      continue
    }
    // dirs doesn't accept positional arguments.
    self.exit_code = 1
    return
  }

  if clear_stack {
    self.set_directory_stack([self.cwd])
    self.exit_code = 0
    return
  }

  let stack = self.get_directory_stack()
  self.render_directory_stack(stack, long_format, one_per_line, numbered)
  self.exit_code = 0
}

fn ExecContext::builtin_pushd(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  self.sync_directory_stack_with_cwd()
  let operands : Array[String] = []
  let mut parse_flags = true

  for arg in args {
    if parse_flags && arg == "--" {
      parse_flags = false
      continue
    }
    if parse_flags && arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 2
      return
    }
    operands.push(arg)
  }

  if operands.length() > 1 {
    self.exit_code = 2
    return
  }

  let stack = self.get_directory_stack()
  if operands.length() == 0 {
    if stack.length() < 2 {
      self.exit_code = 1
      return
    }
    let old_pwd = self.cwd
    let tmp = stack[0]
    stack[0] = stack[1]
    stack[1] = tmp
    self.cwd = stack[0]
    self.env["PWD"] = self.cwd
    self.env["OLDPWD"] = old_pwd
    self.set_directory_stack(stack)
    self.render_directory_stack(stack, false, false, false)
    self.exit_code = 0
    return
  }

  let target = operands[0]
  let resolved = try {
    @fs.resolve_path(self.cwd, target)
  } catch {
    _ => {
      self.exit_code = 1
      return
    }
  }

  match self.fs.entries.get(resolved) {
    Some(@fs.FsEntry::Directory(_)) => {
      let old_pwd = self.cwd
      let new_stack : Array[String] = [resolved]
      for path in stack {
        new_stack.push(path)
      }
      self.cwd = resolved
      self.env["PWD"] = resolved
      self.env["OLDPWD"] = old_pwd
      self.set_directory_stack(new_stack)
      self.render_directory_stack(new_stack, false, false, false)
      self.exit_code = 0
    }
    _ => self.exit_code = 1
  }
}

fn ExecContext::builtin_popd(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  self.sync_directory_stack_with_cwd()
  let mut parse_flags = true
  let operands : Array[String] = []
  for arg in args {
    if parse_flags && arg == "--" {
      parse_flags = false
      continue
    }
    if parse_flags && arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 2
      return
    }
    operands.push(arg)
  }
  if operands.length() > 0 {
    self.exit_code = 2
    return
  }

  let stack = self.get_directory_stack()
  if stack.length() <= 1 {
    self.stdout_buf.write_string("popd: directory stack empty\n")
    self.exit_code = 1
    return
  }

  let old_pwd = self.cwd
  let new_stack : Array[String] = []
  for i = 1; i < stack.length(); i = i + 1 {
    new_stack.push(stack[i])
  }

  self.cwd = new_stack[0]
  self.env["PWD"] = self.cwd
  self.env["OLDPWD"] = old_pwd
  self.set_directory_stack(new_stack)
  self.render_directory_stack(new_stack, false, false, false)
  self.exit_code = 0
}
