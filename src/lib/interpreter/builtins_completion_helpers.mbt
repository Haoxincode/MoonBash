// moon_bash Interpreter - Completion and Directory Builtins

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
