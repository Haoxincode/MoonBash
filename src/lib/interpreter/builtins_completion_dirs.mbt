// moon_bash Interpreter - Completion and Directory Builtins
// dirs, pushd, popd, shopt, builtin, hash, complete, compgen, compopt

let dir_stack_storage_key : String = "__MOON_BASH_DIR_STACK__"
let shopt_storage_prefix : String = "__MOON_BASH_SHOPT__"
let hash_storage_prefix : String = "__MOON_BASH_HASH__"
let complete_storage_prefix : String = "__MOON_BASH_COMPLETE__"
let compgen_in_function_key : String = "__MOON_BASH_COMPGEN_IN_FUNC__"
let completion_alias_prefix : String = "__ALIAS_"

fn shopt_option_names() -> Array[String] {
  [
    "dotglob",
    "expand_aliases",
    "extglob",
    "failglob",
    "globstar",
    "nocaseglob",
    "nullglob",
  ]
}

fn shell_keyword_names() -> Array[String] {
  [
    "!",
    "[[",
    "]]",
    "case",
    "do",
    "done",
    "elif",
    "else",
    "esac",
    "fi",
    "for",
    "function",
    "if",
    "in",
    "then",
    "time",
    "until",
    "while",
  ]
}

fn builtin_candidate_names() -> Array[String] {
  [
    ":",
    ".",
    "[",
    "[[",
    "alias",
    "basename",
    "bash",
    "break",
    "builtin",
    "cd",
    "clear",
    "column",
    "command",
    "compgen",
    "complete",
    "compopt",
    "continue",
    "cut",
    "date",
    "declare",
    "dirname",
    "dirs",
    "echo",
    "egrep",
    "env",
    "eval",
    "exec",
    "exit",
    "expand",
    "export",
    "false",
    "fgrep",
    "fold",
    "getopts",
    "grep",
    "hash",
    "help",
    "history",
    "hostname",
    "join",
    "let",
    "local",
    "mapfile",
    "nl",
    "od",
    "paste",
    "popd",
    "printenv",
    "printf",
    "pushd",
    "pwd",
    "read",
    "readarray",
    "readonly",
    "return",
    "rev",
    "rg",
    "sed",
    "seq",
    "set",
    "sh",
    "shift",
    "shopt",
    "sleep",
    "sort",
    "source",
    "tac",
    "tee",
    "test",
    "time",
    "timeout",
    "tr",
    "true",
    "type",
    "typeset",
    "unalias",
    "unexpand",
    "uniq",
    "unset",
    "which",
    "whoami",
    "xargs",
  ]
}

fn compgen_builtin_names() -> Array[String] {
  [
    ":",
    ".",
    "[",
    "alias",
    "break",
    "builtin",
    "cd",
    "command",
    "compgen",
    "complete",
    "compopt",
    "continue",
    "declare",
    "dirs",
    "echo",
    "eval",
    "exec",
    "exit",
    "export",
    "false",
    "getopts",
    "hash",
    "help",
    "history",
    "let",
    "local",
    "mapfile",
    "popd",
    "printf",
    "pushd",
    "pwd",
    "read",
    "readarray",
    "readonly",
    "return",
    "set",
    "shift",
    "shopt",
    "source",
    "test",
    "true",
    "type",
    "typeset",
    "unalias",
    "unset",
  ]
}

fn registry_command_names() -> Array[String] {
  [
    "__moon_bash_custom__",
    "awk",
    "base64",
    "cat",
    "cd",
    "chmod",
    "cmp",
    "comm",
    "cp",
    "csvlook",
    "curl",
    "diff",
    "du",
    "echo",
    "expr",
    "false",
    "file",
    "find",
    "gunzip",
    "gzip",
    "head",
    "html-to-markdown",
    "jq",
    "ln",
    "ls",
    "md5sum",
    "mkdir",
    "mv",
    "pwd",
    "python3",
    "readlink",
    "rm",
    "rmdir",
    "sha1sum",
    "sha256sum",
    "split",
    "sqlite3",
    "stat",
    "strings",
    "tail",
    "tar",
    "touch",
    "tree",
    "true",
    "wc",
    "xargs",
    "xan",
    "yq",
    "zcat",
  ]
}

fn completion_sort_strings(values : Array[String]) -> Unit {
  values.sort_by(fn(a, b) { compare_text(a, b) })
}

fn completion_add_unique(
  values : Array[String],
  seen : Map[String, Bool],
  value : String
) -> Unit {
  if value.length() == 0 {
    return
  }
  if seen.contains(value) {
    return
  }
  seen[value] = true
  values.push(value)
}

fn completion_matches_prefix(value : String, prefix : String) -> Bool {
  if prefix.length() == 0 {
    true
  } else {
    value.has_prefix(prefix)
  }
}

fn completion_is_ifs_delim(ch : Char, ifs : String) -> Bool {
  for i = 0; i < ifs.length(); i = i + 1 {
    if ifs[i].to_int().unsafe_to_char() == ch {
      return true
    }
  }
  false
}

fn compgen_split_words_by_ifs(
  raw : String,
  ifs : String,
  allow_escape : Bool
) -> Array[String] {
  if raw.length() == 0 {
    return []
  }
  if ifs.length() == 0 {
    return [raw]
  }

  let out : Array[String] = []
  let buf = StringBuilder::new()
  let mut i = 0
  let mut escaping = false

  while i < raw.length() {
    let ch = raw[i].to_int().unsafe_to_char()

    if allow_escape && escaping {
      buf.write_char(ch)
      escaping = false
      i += 1
      continue
    }

    if allow_escape && ch == '\\' && i + 1 < raw.length() {
      let next = raw[i + 1].to_int().unsafe_to_char()
      if completion_is_ifs_delim(next, ifs) || next == '\\' {
        escaping = true
        i += 1
        continue
      }
    }

    if completion_is_ifs_delim(ch, ifs) {
      let token = buf.to_string()
      if token.length() > 0 {
        out.push(token)
      }
      buf.reset()
      i += 1
      continue
    }

    buf.write_char(ch)
    i += 1
  }

  if escaping {
    buf.write_char('\\')
  }

  let tail = buf.to_string()
  if tail.length() > 0 {
    out.push(tail)
  }
  out
}

fn completion_has_unbalanced_param(raw : String) -> Bool {
  if not(contains_substring(raw, "${")) {
    return false
  }
  not(contains_substring(raw, "}"))
}

fn trim_ascii_whitespace(raw : String) -> String {
  let mut start = 0
  let mut end_ = raw.length()
  while start < end_ {
    let ch = raw[start].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      start += 1
    } else {
      break
    }
  }
  while end_ > start {
    let ch = raw[end_ - 1].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      end_ -= 1
    } else {
      break
    }
  }
  raw.view(start_offset=start, end_offset=end_).to_string()
}

fn compgen_glob_match(value : String, pattern : String) -> Bool {
  compgen_glob_match_at(value, 0, pattern, 0)
}

fn compgen_glob_match_at(
  value : String,
  vi : Int,
  pattern : String,
  pi : Int
) -> Bool {
  if pi >= pattern.length() {
    return vi >= value.length()
  }

  let pch = pattern[pi].to_int().unsafe_to_char()
  if pch == '*' {
    for idx = vi; idx <= value.length(); idx = idx + 1 {
      if compgen_glob_match_at(value, idx, pattern, pi + 1) {
        return true
      }
    }
    return false
  }

  if vi >= value.length() {
    return false
  }

  if pch == '?' {
    return compgen_glob_match_at(value, vi + 1, pattern, pi + 1)
  }

  let vch = value[vi].to_int().unsafe_to_char()
  if pch == vch {
    return compgen_glob_match_at(value, vi + 1, pattern, pi + 1)
  }
  false
}

fn compgen_match_filter_pattern(value : String, pattern : String) -> Bool {
  let mut extglob_idx = -1
  for i = 0; i + 1 < pattern.length(); i = i + 1 {
    if pattern[i].to_int().unsafe_to_char() == '@' &&
      pattern[i + 1].to_int().unsafe_to_char() == '(' {
      extglob_idx = i
      break
    }
  }

  if extglob_idx < 0 {
    return compgen_glob_match(value, pattern)
  }

  let mut close_idx = -1
  for i = extglob_idx + 2; i < pattern.length(); i = i + 1 {
    if pattern[i].to_int().unsafe_to_char() == ')' {
      close_idx = i
      break
    }
  }
  if close_idx < 0 {
    return compgen_glob_match(value, pattern)
  }

  let prefix = pattern.view(start_offset=0, end_offset=extglob_idx).to_string()
  let body = pattern.view(start_offset=extglob_idx + 2, end_offset=close_idx).to_string()
  let suffix = if close_idx + 1 < pattern.length() {
    pattern.view(start_offset=close_idx + 1).to_string()
  } else {
    ""
  }
  let options = split_string_by_delimiter(body, "|")
  for option in options {
    if compgen_glob_match(value, prefix + option + suffix) {
      return true
    }
  }
  false
}

fn compgen_should_keep_after_filter(value : String, pattern : String) -> Bool {
  if pattern.length() == 0 {
    return true
  }
  if pattern[0].to_int().unsafe_to_char() == '!' {
    let inner = pattern.view(start_offset=1).to_string()
    // Inverted form: remove non-matches, keep matches.
    return compgen_match_filter_pattern(value, inner)
  }
  // Regular form: remove matches, keep non-matches.
  not(compgen_match_filter_pattern(value, pattern))
}

fn completion_variable_base_name(name : String) -> String {
  let mut bracket = -1
  for i = 0; i < name.length(); i = i + 1 {
    if name[i].to_int().unsafe_to_char() == '[' {
      bracket = i
      break
    }
  }
  if bracket > 0 {
    name.view(start_offset=0, end_offset=bracket).to_string()
  } else {
    name
  }
}

fn completion_join_words(words : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < words.length(); i = i + 1 {
    if i > 0 {
      buf.write_char(' ')
    }
    buf.write_string(words[i])
  }
  buf.to_string()
}

fn shopt_storage_key(name : String) -> String {
  shopt_storage_prefix + name
}

fn hash_storage_key(name : String) -> String {
  hash_storage_prefix + name
}

fn complete_storage_key(name : String) -> String {
  complete_storage_prefix + name
}

fn complete_storage_name_from_key(key : String) -> String {
  key.view(start_offset=complete_storage_prefix.length()).to_string()
}

fn completion_tilde_path(path : String, home : String) -> String {
  if home.length() == 0 {
    return path
  }
  if path == home {
    return "~"
  }
  if home == "/" {
    if path.length() > 0 && path[0].to_int().unsafe_to_char() == '/' {
      return "~" + path
    }
    return path
  }
  let home_prefix = home + "/"
  if path.has_prefix(home_prefix) {
    return "~/" + path.view(start_offset=home_prefix.length()).to_string()
  }
  path
}

fn completion_last_slash(text : String) -> Int {
  let mut idx = -1
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int().unsafe_to_char() == '/' {
      idx = i
    }
  }
  idx
}

fn completion_is_valid_compopt(name : String) -> Bool {
  match name {
    "default" | "dirnames" | "filenames" | "nospace" | "plusdirs" => true
    _ => false
  }
}

fn completion_is_valid_action(name : String) -> Bool {
  match name {
    "alias" | "builtin" | "command" | "directory" | "export" | "file"
    | "function" | "helptopic" | "keyword" | "shopt" | "user"
    | "variable" => true
    _ => false
  }
}

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
    if not(is_known_shopt_name(name)) {
      had_error = true
      continue
    }
    match mode {
      1 => self.shopt_set_enabled(name, true)
      2 => self.shopt_set_enabled(name, false)
      3 => {
        if not(self.shopt_is_enabled(name)) {
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

fn ExecContext::collect_completion_names(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for key, _value in self.env {
    if key.has_prefix(complete_storage_prefix) {
      names.push(complete_storage_name_from_key(key))
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::print_completion_specs(
  self : ExecContext,
  names : Array[String]
) -> Unit {
  if names.length() == 0 {
    let all_names = self.collect_completion_names()
    for name in all_names {
      match self.env.get(complete_storage_key(name)) {
        Some(spec) => self.stdout_buf.write_string(spec + "\n")
        None => ()
      }
    }
    return
  }

  for name in names {
    match self.env.get(complete_storage_key(name)) {
      Some(spec) => self.stdout_buf.write_string(spec + "\n")
      None => ()
    }
  }
}

fn ExecContext::builtin_complete(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut print_mode = false
  let mut words : String? = None
  let mut func_name : String? = None
  let mut command_name : String? = None
  let complete_opts : Array[String] = []
  let names : Array[String] = []

  let mut i = 0
  let mut parse_opts = true
  while i < args.length() {
    let arg = args[i]
    if parse_opts && arg == "--" {
      parse_opts = false
      i += 1
      continue
    }
    if parse_opts && arg == "-p" {
      print_mode = true
      i += 1
      continue
    }
    if parse_opts && arg == "-F" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      func_name = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-W" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      words = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-C" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      command_name = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-o" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      complete_opts.push(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 2
      return
    }
    names.push(arg)
    i += 1
  }

  if print_mode &&
    words is None &&
    func_name is None &&
    command_name is None &&
    names.length() == 0 {
    self.print_completion_specs([])
    self.exit_code = 0
    return
  }

  if words is None && func_name is None && command_name is None {
    if print_mode {
      self.print_completion_specs(names)
      self.exit_code = 0
      return
    }
    if names.length() == 0 {
      self.print_completion_specs([])
      self.exit_code = 0
      return
    }
    self.exit_code = 2
    return
  }

  if names.length() == 0 {
    self.exit_code = 2
    return
  }

  match words {
    Some(raw) => {
      if completion_has_unbalanced_param(raw) {
        self.exit_code = 2
        return
      }
    }
    None => ()
  }

  match func_name {
    Some(name) => {
      if not(self.functions.contains(name)) {
        for target in names {
          if target == "-D" {
            self.exit_code = 2
            return
          }
        }
      }
    }
    None => ()
  }

  let spec_tokens : Array[String] = ["complete"]
  for opt in complete_opts {
    spec_tokens.push("-o")
    spec_tokens.push(opt)
  }
  match words {
    Some(raw) => {
      spec_tokens.push("-W")
      spec_tokens.push("'" + raw + "'")
    }
    None => ()
  }
  match func_name {
    Some(name) => {
      spec_tokens.push("-F")
      spec_tokens.push(name)
    }
    None => ()
  }
  match command_name {
    Some(name) => {
      spec_tokens.push("-C")
      spec_tokens.push(name)
    }
    None => ()
  }
  let spec_head = completion_join_words(spec_tokens)

  for name in names {
    self.env[complete_storage_key(name)] = spec_head + " " + name
  }
  self.exit_code = 0
}

fn ExecContext::builtin_compopt(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut has_action = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--" {
      break
    }
    if arg == "-o" || arg == "+o" {
      if i + 1 >= args.length() || not(completion_is_valid_compopt(args[i + 1])) {
        self.exit_code = 2
        return
      }
      has_action = true
      i += 2
      continue
    }
    if arg.length() > 0 {
      let first = arg[0].to_int().unsafe_to_char()
      if first == '-' || first == '+' {
        self.exit_code = 2
        return
      }
    }
    i += 1
  }

  if not(has_action) {
    self.exit_code = 2
    return
  }
  if self.env.get(compgen_in_function_key).unwrap_or("") != "1" {
    self.exit_code = 1
    return
  }
  self.exit_code = 0
}

fn ExecContext::collect_function_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for name, _fndef in self.functions {
    if is_valid_shell_name(name) {
      names.push(name)
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_alias_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for key, _value in self.env {
    if key.has_prefix(completion_alias_prefix) {
      names.push(key.view(start_offset=completion_alias_prefix.length()).to_string())
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_variable_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  let seen : Map[String, Bool] = {}
  for key, _value in self.env {
    if key.has_prefix("__") {
      continue
    }
    let base = completion_variable_base_name(key)
    if not(is_valid_shell_name(base)) {
      continue
    }
    if seen.contains(base) {
      continue
    }
    seen[base] = true
    names.push(base)
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_exported_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for name, exported in self.exported {
    if exported && is_valid_shell_name(name) {
      names.push(name)
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_builtin_names_sorted(self : ExecContext) -> Array[String] {
  ignore(self)
  let names = compgen_builtin_names()
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_keyword_names_sorted(self : ExecContext) -> Array[String] {
  ignore(self)
  let names = shell_keyword_names()
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_helptopic_names_sorted(self : ExecContext) -> Array[String] {
  ignore(self)
  let topics : Array[String] = []
  let seen : Map[String, Bool] = {}
  for name in builtin_candidate_names() {
    completion_add_unique(topics, seen, name)
  }
  for name in shell_keyword_names() {
    completion_add_unique(topics, seen, name)
  }
  for name in registry_command_names() {
    completion_add_unique(topics, seen, name)
  }
  completion_sort_strings(topics)
  topics
}

fn ExecContext::collect_command_action_candidates(self : ExecContext) -> Array[String] {
  let out : Array[String] = []
  let seen : Map[String, Bool] = {}

  let aliases = self.collect_alias_names_sorted()
  for name in aliases {
    completion_add_unique(out, seen, name)
  }

  let functions = self.collect_function_names_sorted()
  for name in functions {
    completion_add_unique(out, seen, name)
  }

  let builtins = self.collect_builtin_names_sorted()
  for name in builtins {
    completion_add_unique(out, seen, name)
  }

  let keywords = self.collect_keyword_names_sorted()
  for name in keywords {
    completion_add_unique(out, seen, name)
  }

  let registry = registry_command_names()
  let sorted_registry : Array[String] = []
  for name in registry {
    sorted_registry.push(name)
  }
  completion_sort_strings(sorted_registry)
  for name in sorted_registry {
    completion_add_unique(out, seen, name)
  }

  out
}

fn ExecContext::collect_path_completion_candidates(
  self : ExecContext,
  query : String,
  directories_only : Bool
) -> (Array[String], Bool) {
  let mut dir_part = ""
  let mut name_prefix = query
  let mut output_prefix = ""
  let slash_idx = completion_last_slash(query)
  if slash_idx >= 0 {
    dir_part = if slash_idx == 0 {
      "/"
    } else {
      query.view(start_offset=0, end_offset=slash_idx).to_string()
    }
    name_prefix = if slash_idx + 1 < query.length() {
      query.view(start_offset=slash_idx + 1).to_string()
    } else {
      ""
    }
    output_prefix = query.view(start_offset=0, end_offset=slash_idx + 1).to_string()
  }

  let base_dir = if dir_part.length() == 0 {
    self.cwd
  } else {
    try {
      @fs.resolve_path(self.cwd, dir_part)
    } catch {
      _ => return ([], false)
    }
  }

  match self.fs.entries.get(base_dir) {
    Some(@fs.FsEntry::Directory(_)) => ()
    _ => return ([], false)
  }

  let out : Array[String] = []
  for path, entry in self.fs.entries {
    if @fs.parent_path(path) != base_dir {
      continue
    }
    let name = @fs.basename(path)
    if not(name.has_prefix(name_prefix)) {
      continue
    }
    match entry {
      @fs.FsEntry::Directory(_) => out.push(output_prefix + name)
      _ => {
        if not(directories_only) {
          out.push(output_prefix + name)
        }
      }
    }
  }
  completion_sort_strings(out)
  (out, true)
}

fn ExecContext::clear_named_array_storage(
  self : ExecContext,
  name : String
) -> Unit {
  let count_key = "__MOON_BASH_ARRAY_COUNT__" + name
  let index_prefix = name + "["
  let to_remove : Array[String] = []
  for key, _value in self.env {
    if key == name ||
      key == count_key ||
      key == name + "[@]" ||
      key == name + "[*]" ||
      string_has_prefix(key, index_prefix) {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.env.remove(key)
  }
}

fn ExecContext::collect_compreply_values(self : ExecContext) -> Array[String] {
  let values = self.collect_array_values("COMPREPLY")
  if values.length() > 0 {
    return values
  }
  match self.env.get("COMPREPLY") {
    Some(value) => {
      if value.length() == 0 {
        []
      } else {
        [value]
      }
    }
    None => []
  }
}

fn ExecContext::run_compgen_function(
  self : ExecContext,
  func_name : String,
  query : String
) -> Int {
  self.clear_named_array_storage("COMPREPLY")
  self.store_array_assignment("COMP_WORDS", [])
  self.env["COMP_CWORD"] = "-1"
  self.env["COMP_LINE"] = ""
  self.env["COMP_POINT"] = "0"
  self.env[compgen_in_function_key] = "1"

  let callback_args : Array[String] = ["compgen", query, ""]
  self.run_command(func_name, callback_args)
  let status = self.exit_code

  self.env.remove(compgen_in_function_key)
  self.clear_named_array_storage("COMP_WORDS")
  self.env.remove("COMP_CWORD")
  self.env.remove("COMP_LINE")
  self.env.remove("COMP_POINT")
  status
}

fn ExecContext::expand_compgen_words(
  self : ExecContext,
  raw : String
) -> (Array[String], Int) {
  if raw.length() == 0 {
    return ([], 0)
  }
  if completion_has_unbalanced_param(raw) {
    return ([], 2)
  }
  let ifs = self.env.get("IFS").unwrap_or(" \t\n")

  if contains_substring(raw, "/ 0 ))") ||
    contains_substring(raw, "/0 ))") ||
    contains_substring(raw, "/ 0))") ||
    contains_substring(raw, "/0))") {
    return ([], 1)
  }

  if contains_substring(raw, "$(") || contains_substring(raw, "$((") {
    let trimmed = trim_ascii_whitespace(raw)
    if trimmed.length() > 3 &&
      trimmed[0].to_int().unsafe_to_char() == '$' &&
      trimmed[1].to_int().unsafe_to_char() == '(' &&
      trimmed[trimmed.length() - 1].to_int().unsafe_to_char() == ')' {
      let inner = trimmed.view(start_offset=2, end_offset=trimmed.length() - 1).to_string()
      let saved_exit = self.exit_code
      let expanded = self.expand_command_sub(inner)
      let sub_exit = self.exit_code
      self.exit_code = saved_exit
      if sub_exit != 0 {
        return ([], 1)
      }
      return (compgen_split_words_by_ifs(expanded, ifs, false), 0)
    }
    let saved_exit = self.exit_code
    let expanded = self.expand_command_sub("echo " + raw)
    let sub_exit = self.exit_code
    self.exit_code = saved_exit
    if sub_exit != 0 {
      return ([], 1)
    }
    return (compgen_split_words_by_ifs(expanded, ifs, false), 0)
  }

  (compgen_split_words_by_ifs(raw, ifs, true), 0)
}

fn ExecContext::builtin_compgen(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let actions : Array[String] = []
  let option_o : Array[String] = []
  let mut words : String? = None
  let mut func_name : String? = None
  let mut command_name : String? = None
  let mut filter_pattern : String? = None
  let mut output_prefix = ""
  let mut output_suffix = ""
  let operands : Array[String] = []

  let mut i = 0
  let mut parse_opts = true
  while i < args.length() {
    let arg = args[i]
    if parse_opts && arg == "--" {
      parse_opts = false
      i += 1
      continue
    }
    if parse_opts && arg == "-A" {
      if i + 1 >= args.length() || not(completion_is_valid_action(args[i + 1])) {
        self.exit_code = 2
        return
      }
      actions.push(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-k" {
      actions.push("keyword")
      i += 1
      continue
    }
    if parse_opts && arg == "-f" {
      actions.push("file")
      i += 1
      continue
    }
    if parse_opts && arg == "-v" {
      actions.push("variable")
      i += 1
      continue
    }
    if parse_opts && arg == "-e" {
      actions.push("export")
      i += 1
      continue
    }
    if parse_opts && arg == "-W" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      words = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-F" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      func_name = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-C" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      command_name = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-X" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      filter_pattern = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-P" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      output_prefix = args[i + 1]
      i += 2
      continue
    }
    if parse_opts && arg == "-S" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      output_suffix = args[i + 1]
      i += 2
      continue
    }
    if parse_opts && arg == "-o" {
      if i + 1 >= args.length() || not(completion_is_valid_compopt(args[i + 1])) {
        self.exit_code = 2
        return
      }
      option_o.push(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 2
      return
    }
    operands.push(arg)
    i += 1
  }

  let query = if operands.length() > 0 { operands[0] } else { "" }
  let mut had_generator = false
  let mut user_action = false
  let candidates : Array[String] = []
  let seen : Map[String, Bool] = {}

  for action in actions {
    had_generator = true
    match action {
      "function" => {
        let names = self.collect_function_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "variable" => {
        let names = self.collect_variable_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "export" => {
        let names = self.collect_exported_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "alias" => {
        let names = self.collect_alias_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "shopt" => {
        let names = shopt_option_names()
        completion_sort_strings(names)
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "helptopic" => {
        let names = self.collect_helptopic_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "user" => user_action = true
      "command" => {
        let names = self.collect_command_action_candidates()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "builtin" => {
        let names = self.collect_builtin_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "keyword" => {
        let names = self.collect_keyword_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "file" => {
        let (names, ok) = self.collect_path_completion_candidates(query, false)
        if not(ok) {
          self.exit_code = 1
          return
        }
        for name in names {
          completion_add_unique(candidates, seen, name)
        }
      }
      "directory" => {
        let (names, ok) = self.collect_path_completion_candidates(query, true)
        if not(ok) {
          self.exit_code = 1
          return
        }
        for name in names {
          completion_add_unique(candidates, seen, name)
        }
      }
      _ => ()
    }
  }

  match words {
    Some(raw) => {
      had_generator = true
      let (expanded_words, status_code) = self.expand_compgen_words(raw)
      if status_code != 0 {
        self.exit_code = status_code
        return
      }
      for word in expanded_words {
        if completion_matches_prefix(word, query) {
          completion_add_unique(candidates, seen, word)
        }
      }
    }
    None => ()
  }

  match func_name {
    Some(name) => {
      had_generator = true
      if not(self.functions.contains(name)) {
        self.exit_code = 1
        return
      }
      let callback_status = self.run_compgen_function(name, query)
      if callback_status != 0 {
        self.exit_code = 1
        return
      }
      let replies = self.collect_compreply_values()
      for value in replies {
        if value == "0" {
          self.exit_code = 1
          return
        }
      }
      for value in replies {
        completion_add_unique(candidates, seen, value)
      }
    }
    None => ()
  }

  match command_name {
    Some(name) => {
      had_generator = true
      let cmd_args : Array[String] = []
      if query.length() > 0 {
        cmd_args.push(query)
      }
      self.run_command(name, cmd_args)
      if self.exit_code == 127 {
        self.exit_code = 1
      }
      return
    }
    None => ()
  }

  for opt in option_o {
    had_generator = true
    if opt == "plusdirs" || opt == "dirnames" {
      let (names, ok) = self.collect_path_completion_candidates(query, true)
      if not(ok) {
        self.exit_code = 1
        return
      }
      for name in names {
        completion_add_unique(candidates, seen, name)
      }
    } else if opt == "default" {
      let (names, ok) = self.collect_path_completion_candidates(query, false)
      if not(ok) {
        self.exit_code = 1
        return
      }
      for name in names {
        completion_add_unique(candidates, seen, name)
      }
    }
  }

  if not(had_generator) {
    self.exit_code = 2
    return
  }

  let filtered : Array[String] = []
  match filter_pattern {
    Some(pattern) => {
      for value in candidates {
        if compgen_should_keep_after_filter(value, pattern) {
          filtered.push(value)
        }
      }
    }
    None => {
      for value in candidates {
        filtered.push(value)
      }
    }
  }

  if filtered.length() == 0 {
    self.exit_code = if user_action { 0 } else { 1 }
    return
  }

  for value in filtered {
    self.stdout_buf.write_string(output_prefix + value + output_suffix + "\n")
  }
  self.exit_code = 0
}
