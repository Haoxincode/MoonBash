// moon_bash Interpreter - shopt, builtin, hash Builtins

fn is_known_shopt_name(name : String) -> Bool {
  for known in shopt_option_names() {
    if known == name {
      return true
    }
  }
  false
}

fn ExecContext::shopt_is_enabled(self : ExecContext, name : String) -> Bool {
  self.env.get(shopt_storage_key(name)).unwrap_or("0") == "1"
}

fn ExecContext::shopt_set_enabled(
  self : ExecContext,
  name : String,
  enabled : Bool
) -> Unit {
  self.env[shopt_storage_key(name)] = if enabled { "1" } else { "0" }
}

fn ExecContext::print_shopt_state(
  self : ExecContext,
  name : String
) -> Unit {
  let enabled = self.shopt_is_enabled(name)
  let flag = if enabled { "s" } else { "u" }
  self.stdout_buf.write_string("shopt -\{flag} \{name}\n")
}

fn ExecContext::builtin_shopt(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // Mode:
  // 0 = print
  // 1 = set
  // 2 = unset
  // 3 = query
  let mut mode = 0
  let names : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--" {
      for j = i + 1; j < args.length(); j = j + 1 {
        names.push(args[j])
      }
      break
    }
    match arg {
      "-s" => {
        mode = 1
        i += 1
        continue
      }
      "-u" => {
        mode = 2
        i += 1
        continue
      }
      "-q" => {
        mode = 3
        i += 1
        continue
      }
      "-p" => {
        mode = 0
        i += 1
        continue
      }
      _ => ()
    }

    if arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 1
      return
    }
    names.push(arg)
    i += 1
  }

  if names.length() == 0 && mode == 0 {
    let options = shopt_option_names()
    for name in options {
      self.print_shopt_state(name)
    }
    self.exit_code = 0
    return
  }

  let mut had_error = false
  let mut any_unset_in_query = false
  for name in names {
    if !(is_known_shopt_name(name)) {
      had_error = true
      continue
    }
    match mode {
      1 => self.shopt_set_enabled(name, true)
      2 => self.shopt_set_enabled(name, false)
      3 => {
        if !(self.shopt_is_enabled(name)) {
          any_unset_in_query = true
        }
      }
      _ => self.print_shopt_state(name)
    }
  }

  if mode == 3 {
    self.exit_code = if had_error || any_unset_in_query { 1 } else { 0 }
  } else {
    self.exit_code = if had_error { 1 } else { 0 }
  }
}

fn ExecContext::builtin_builtin_cd(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let target = if args.length() == 0 {
    self.env.get("HOME").unwrap_or("/home/user")
  } else if args[0] == "-" {
    self.env.get("OLDPWD").unwrap_or(self.cwd)
  } else {
    args[0]
  }

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
      self.cwd = resolved
      self.env["PWD"] = resolved
      self.env["OLDPWD"] = old_pwd
      self.sync_directory_stack_with_cwd()
      self.remember_hashed_command("cd")
      self.exit_code = 0
    }
    _ => self.exit_code = 1
  }
}

fn ExecContext::builtin_builtin(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut start = 0
  if args.length() > 0 && args[0] == "--" {
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

  if cmd_name == "cd" {
    self.builtin_builtin_cd(cmd_args)
    return
  }

  if self.run_builtin(cmd_name, cmd_args) {
    return
  }
  self.exit_code = 1
}

fn ExecContext::remember_hashed_command(
  self : ExecContext,
  name : String
) -> Unit {
  if name.length() == 0 || contains_slash(name) {
    return
  }
  self.remember_hashed_command_path(name, "/usr/bin/" + name)
}

fn ExecContext::builtin_hash(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    let values : Array[String] = []
    for key, value in self.env {
      if key.has_prefix(hash_storage_prefix) {
        values.push(value)
      }
    }
    completion_sort_strings(values)
    for value in values {
      self.stdout_buf.write_string(value + "\n")
    }
    self.exit_code = 0
    return
  }

  if args[0] == "-r" {
    if args.length() > 1 {
      self.exit_code = 1
      return
    }
    let remove_keys : Array[String] = []
    for key, _value in self.env {
      if key.has_prefix(hash_storage_prefix) {
        remove_keys.push(key)
      }
    }
    for key in remove_keys {
      self.env.remove(key)
    }
    self.exit_code = 0
    return
  }

  let mut all_found = true
  for name in args {
    if is_shell_builtin(name) ||
      self.functions.contains(name) ||
      @commands.find_command(name) is Some(_) {
      self.remember_hashed_command(name)
    } else {
      all_found = false
    }
  }
  self.exit_code = if all_found { 0 } else { 1 }
}
