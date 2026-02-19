// moon_bash Interpreter - Command Lookup Helpers
// Shared lookup utilities for command/type/which/path execution behavior.

let default_command_path : String = "/usr/bin:/bin"
let command_alias_prefix : String = "__ALIAS_"
let command_skip_function_lookup_key : String = "__MOON_BASH_SKIP_FUNCTION_LOOKUP"
let command_default_path_lookup_key : String = "__MOON_BASH_COMMAND_USE_DEFAULT_PATH"

fn is_lookup_shell_builtin(name : String) -> Bool {
  match name {
    ":" | "." | "[" | "[[" | "alias" | "break" | "builtin" | "cd"
    | "command" | "compgen" | "complete" | "compopt" | "continue"
    | "declare" | "dirs" | "echo" | "eval" | "exec" | "exit"
    | "export" | "false" | "getopts" | "hash" | "help" | "history"
    | "let" | "local" | "mapfile" | "popd" | "printf" | "pushd"
    | "pwd" | "read" | "readarray" | "readonly" | "return" | "set"
    | "shift" | "shopt" | "source" | "test" | "true" | "type"
    | "typeset" | "unalias" | "unset" => true
    _ => false
  }
}

fn is_special_shell_builtin(name : String) -> Bool {
  match name {
    ":" | "." | "break" | "continue" | "eval" | "exec" | "exit"
    | "export" | "readonly" | "return" | "set" | "shift"
    | "unset" => true
    _ => false
  }
}

fn is_lookup_shell_keyword(name : String) -> Bool {
  match name {
    "!" | "[[" | "]]" | "case" | "do" | "done" | "elif" | "else"
    | "esac" | "fi" | "for" | "function" | "if" | "in" | "then"
    | "time" | "until" | "while" | "{" | "}" => true
    _ => false
  }
}

fn command_has_virtual_external(name : String) -> Bool {
  if @commands.find_command(name) is Some(_) {
    return true
  }
  is_shell_builtin(name) && not(is_lookup_shell_builtin(name))
}

fn command_mode_has_execute_permission(mode : Int) -> Bool {
  (mode & 0o111) != 0
}

fn command_path_display_candidate(path_dir : String, name : String) -> String {
  if path_dir.length() == 0 {
    return name
  }
  if path_dir == "/" {
    return "/" + name
  }
  if path_dir[path_dir.length() - 1].to_int().unsafe_to_char() == '/' {
    return path_dir + name
  }
  path_dir + "/" + name
}

fn command_is_executable_entry(entry : @fs.FsEntry) -> Bool {
  match entry {
    @fs.FsEntry::File(data) => command_mode_has_execute_permission(data.mode)
    @fs.FsEntry::Symlink(data) => command_mode_has_execute_permission(data.mode)
    _ => false
  }
}

fn ExecContext::lookup_alias_value(
  self : ExecContext,
  name : String
) -> String? {
  self.env.get(command_alias_prefix + name)
}

fn ExecContext::skip_function_lookup_enabled(self : ExecContext) -> Bool {
  self.env.get(command_skip_function_lookup_key).unwrap_or("") == "1"
}

fn ExecContext::default_path_lookup_enabled(self : ExecContext) -> Bool {
  self.env.get(command_default_path_lookup_key).unwrap_or("") == "1"
}

fn ExecContext::lookup_hashed_command_path(
  self : ExecContext,
  name : String
) -> String? {
  self.env.get(hash_storage_key(name))
}

fn ExecContext::remember_hashed_command_path(
  self : ExecContext,
  name : String,
  path : String
) -> Unit {
  if name.length() == 0 || contains_slash(name) {
    return
  }
  self.env[hash_storage_key(name)] = path
}

fn ExecContext::clear_hashed_command(
  self : ExecContext,
  name : String
) -> Unit {
  self.env.remove(hash_storage_key(name))
}

fn ExecContext::collect_path_command_matches(
  self : ExecContext,
  name : String,
  use_default_path : Bool,
  include_virtual_fallback : Bool,
  stop_after_first : Bool
) -> Array[(String, String, Bool)] {
  let matches : Array[(String, String, Bool)] = []
  let seen : Map[String, Bool] = {}
  if name.length() == 0 {
    return matches
  }

  if contains_slash(name) {
    let resolved = try {
      @fs.resolve_path(self.cwd, name)
    } catch {
      _ => return matches
    }
    match self.fs.entries.get(resolved) {
      Some(entry) => {
        if command_is_executable_entry(entry) {
          matches.push((name, resolved, false))
        }
      }
      None => ()
    }
    return matches
  }

  let path_spec = if use_default_path {
    default_command_path
  } else {
    self.env.get("PATH").unwrap_or("")
  }
  let path_dirs = split_string_by_delimiter(path_spec, ":")

  for path_dir in path_dirs {
    let display = command_path_display_candidate(path_dir, name)
    let resolved = try {
      @fs.resolve_path(self.cwd, display)
    } catch {
      _ => continue
    }
    let mut candidate_missing = false
    match self.fs.entries.get(resolved) {
      Some(entry) => {
        if not(command_is_executable_entry(entry)) {
          ()
        } else {
          if seen.contains(display) {
            continue
          }
          seen[display] = true
          matches.push((display, resolved, false))
          if stop_after_first {
            return matches
          }
        }
      }
      None => candidate_missing = true
    }

    if include_virtual_fallback &&
      candidate_missing &&
      (path_dir == "/usr/bin" || path_dir == "/bin") &&
      command_has_virtual_external(name) {
      if seen.contains(display) {
        continue
      }
      seen[display] = true
      matches.push((display, resolved, true))
      if stop_after_first {
        return matches
      }
    }
  }
  matches
}

fn ExecContext::first_path_command_match(
  self : ExecContext,
  name : String,
  use_default_path : Bool,
  include_virtual_fallback : Bool
) -> (String, String, Bool)? {
  let matches = self.collect_path_command_matches(
    name,
    use_default_path,
    include_virtual_fallback,
    true,
  )
  if matches.length() == 0 {
    None
  } else {
    Some(matches[0])
  }
}

fn ExecContext::all_path_command_matches(
  self : ExecContext,
  name : String,
  use_default_path : Bool,
  include_virtual_fallback : Bool
) -> Array[(String, String, Bool)] {
  self.collect_path_command_matches(
    name,
    use_default_path,
    include_virtual_fallback,
    false,
  )
}
