// MoonBash Entry Point - Exported functions for JS consumption

/// Execute a bash script with default settings.
/// Returns a JSON string: {"stdout":"...","stderr":"...","exitCode":N}
pub fn execute(script : String) -> String {
  let fs = @fs.InMemoryFs::new()
  let ctx = @interpreter.ExecContext::new(fs)
  let result = ctx.execute(script)
  result_to_json(result)
}

/// Execute a bash script with initial filesystem files and environment.
/// env_json: JSON object of env vars, e.g. {"USER":"agent","HOME":"/home/agent"}
/// files_json: JSON object of path->content, e.g. {"/tmp/a.txt":"hello"}
/// cwd: working directory, e.g. "/home/user"
pub fn execute_with_fs(
  script : String,
  env_json : String,
  files_json : String,
  cwd : String
) -> String {
  execute_with_state(
    script,
    env_json,
    files_json,
    "{}",
    "{}",
    "{}",
    cwd,
    "{}",
    "default",
  )
}

/// Execute a bash script and return result plus filesystem snapshot.
/// dirs_json: JSON object with directory paths as keys.
/// links_json: JSON object of symlink path->target.
/// modes_json: JSON object of path->mode (decimal string).
pub fn execute_with_state(
  script : String,
  env_json : String,
  files_json : String,
  dirs_json : String,
  links_json : String,
  modes_json : String,
  cwd : String,
  limits_json : String,
  layout_mode : String
) -> String {
  let fs = @fs.InMemoryFs::new()

  // Parse and apply dirs
  let dir_entries = parse_json_object(dirs_json)
  for i = 0; i < dir_entries.length(); i = i + 1 {
    let (path, _value) = dir_entries[i]
    try { fs.mkdir(path, recursive=true) } catch { _ => () }
  }

  // Parse and apply files
  let file_entries = parse_json_object(files_json)
  for i = 0; i < file_entries.length(); i = i + 1 {
    let (path, content) = file_entries[i]
    // Ensure parent directories exist
    ensure_parents(fs, path)
    try { fs.write_file(path, content) } catch { _ => () }
  }

  // Parse and apply symlinks
  let link_entries = parse_json_object(links_json)
  for i = 0; i < link_entries.length(); i = i + 1 {
    let (path, target) = link_entries[i]
    try { fs.symlink(target, path) } catch { _ => () }
  }

  // Parse and apply modes
  let mode_entries = parse_json_object(modes_json)
  for i = 0; i < mode_entries.length(); i = i + 1 {
    let (path, mode_str) = mode_entries[i]
    let mode = parse_decimal_int(mode_str)
    try { fs.chmod(path, mode) } catch { _ => () }
  }

  let actual_cwd = if cwd.length() > 0 { cwd } else { "/home/user" }

  // Optionally strip default /home/user layout for explicit-layout mode.
  if layout_mode == "minimal" && not(needs_home_user_layout(
    file_entries,
    dir_entries,
    link_entries,
    actual_cwd,
  )) {
    try { fs.rm("/home/user", recursive=true) } catch { _ => () }
  }

  // Parse env vars
  let env : Map[String, String] = {}
  let env_entries = parse_json_object(env_json)
  for i = 0; i < env_entries.length(); i = i + 1 {
    let (key, value) = env_entries[i]
    env[key] = value
  }

  // Parse and apply execution limits
  let limits = parse_limits(limits_json)
  // Ensure cwd exists for relative-path commands in empty fixtures.
  try { fs.mkdir(actual_cwd, recursive=true) } catch { _ => () }
  let ctx = @interpreter.ExecContext::new(
    fs,
    env=env,
    cwd=actual_cwd,
    limits=limits,
  )
  let result = ctx.execute(script)

  let files_out : Array[(String, String)] = []
  let dirs_out : Array[(String, String)] = []
  let links_out : Array[(String, String)] = []
  let modes_out : Array[(String, String)] = []
  for entry in fs.snapshot_entries() {
    let (path, kind, data, mode) = entry
    modes_out.push((path, mode))
    if kind == "f" {
      files_out.push((path, data))
    } else if kind == "d" {
      dirs_out.push((path, "1"))
    } else if kind == "l" {
      links_out.push((path, data))
    }
  }
  let env_out : Array[(String, String)] = []
  for key, value in ctx.env {
    env_out.push((key, value))
  }
  env_out.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  result_with_state_to_json(
    result,
    files_out,
    dirs_out,
    links_out,
    modes_out,
    env_out,
  )
}

// ============================================================================
// JSON helpers (no dependencies - hand-rolled)
// ============================================================================

/// Convert ExecResult to JSON string
fn result_to_json(result : @ast.ExecResult) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"stdout\":")
  buf.write_string(json_escape_string(result.stdout))
  buf.write_string(",\"stderr\":")
  buf.write_string(json_escape_string(result.stderr))
  buf.write_string(",\"exitCode\":")
  buf.write_string(result.exit_code.to_string())
  buf.write_string("}")
  buf.to_string()
}

/// Convert ExecResult + filesystem snapshot to JSON string.
fn result_with_state_to_json(
  result : @ast.ExecResult,
  files : Array[(String, String)],
  dirs : Array[(String, String)],
  links : Array[(String, String)],
  modes : Array[(String, String)],
  env : Array[(String, String)]
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"stdout\":")
  buf.write_string(json_escape_string(result.stdout))
  buf.write_string(",\"stderr\":")
  buf.write_string(json_escape_string(result.stderr))
  buf.write_string(",\"exitCode\":")
  buf.write_string(result.exit_code.to_string())
  buf.write_string(",\"files\":")
  buf.write_string(json_object_from_pairs(files))
  buf.write_string(",\"dirs\":")
  buf.write_string(json_object_from_pairs(dirs))
  buf.write_string(",\"links\":")
  buf.write_string(json_object_from_pairs(links))
  buf.write_string(",\"modes\":")
  buf.write_string(json_object_from_pairs(modes))
  buf.write_string(",\"env\":")
  buf.write_string(json_object_from_pairs(env))
  buf.write_string("}")
  buf.to_string()
}

/// Convert string pairs into a JSON object.
fn json_object_from_pairs(pairs : Array[(String, String)]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('{')
  for i = 0; i < pairs.length(); i = i + 1 {
    if i > 0 {
      buf.write_char(',')
    }
    let (k, v) = pairs[i]
    buf.write_string(json_escape_string(k))
    buf.write_char(':')
    buf.write_string(json_escape_string(v))
  }
  buf.write_char('}')
  buf.to_string()
}

/// Escape a string for JSON output
fn json_escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => {
        let code = ch.to_int()
        if code < 0x20 {
          buf.write_string("\\u00")
          let hi = code / 16
          let lo = code % 16
          buf.write_char(hex_digit(hi))
          buf.write_char(hex_digit(lo))
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

fn hex_digit(n : Int) -> Char {
  if n < 10 {
    (n + 48).unsafe_to_char() // '0' = 48
  } else {
    (n - 10 + 97).unsafe_to_char() // 'a' = 97
  }
}

/// Parse a simple JSON object {"key":"value",...} into array of (key, value) pairs.
/// Only supports string values. No nesting.
fn parse_json_object(json : String) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let len = json.length()
  if len < 2 {
    return result
  }
  let mut i = 0
  // Skip whitespace and opening brace
  while i < len {
    let ch = json[i].to_int().unsafe_to_char()
    if ch == '{' {
      i += 1
      break
    }
    i += 1
  }
  // Parse key-value pairs
  while i < len {
    // Skip whitespace
    while i < len {
      let ch = json[i].to_int().unsafe_to_char()
      if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
        i += 1
      } else {
        break
      }
    }
    if i >= len {
      break
    }
    let ch = json[i].to_int().unsafe_to_char()
    if ch == '}' {
      break
    }
    if ch == ',' {
      i += 1
      continue
    }
    // Parse key (must be a quoted string)
    if ch == '"' {
      let (key, next_i) = parse_json_string(json, i)
      i = next_i
      // Skip colon
      while i < len {
        let c = json[i].to_int().unsafe_to_char()
        if c == ':' {
          i += 1
          break
        }
        i += 1
      }
      // Skip whitespace
      while i < len {
        let c = json[i].to_int().unsafe_to_char()
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
          i += 1
        } else {
          break
        }
      }
      // Parse value
      if i < len && json[i].to_int().unsafe_to_char() == '"' {
        let (value, next_i2) = parse_json_string(json, i)
        i = next_i2
        result.push((key, value))
      } else {
        // Skip non-string value
        while i < len {
          let c = json[i].to_int().unsafe_to_char()
          if c == ',' || c == '}' {
            break
          }
          i += 1
        }
      }
    } else {
      i += 1
    }
  }
  result
}

/// Parse a JSON string starting at position i (must be at opening quote).
/// Returns (unescaped string, position after closing quote).
fn parse_json_string(json : String, start : Int) -> (String, Int) {
  let buf = StringBuilder::new()
  let len = json.length()
  let mut i = start + 1 // skip opening quote
  while i < len {
    let ch = json[i].to_int().unsafe_to_char()
    if ch == '"' {
      return (buf.to_string(), i + 1)
    }
    if ch == '\\' && i + 1 < len {
      i += 1
      let esc = json[i].to_int().unsafe_to_char()
      match esc {
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        '/' => buf.write_char('/')
        _ => {
          buf.write_char('\\')
          buf.write_char(esc)
        }
      }
    } else {
      buf.write_char(ch)
    }
    i += 1
  }
  (buf.to_string(), i)
}

fn parse_decimal_int(s : String) -> Int {
  let mut value = 0
  let mut sign = 1
  let mut i = 0
  if s.length() > 0 && s[0].to_int().unsafe_to_char() == '-' {
    sign = -1
    i = 1
  }
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      break
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    i += 1
  }
  value * sign
}

fn starts_with(prefix_target : String, prefix : String) -> Bool {
  if prefix.length() > prefix_target.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if prefix_target[i] != prefix[i] {
      return false
    }
  }
  true
}

fn needs_home_user_layout(
  file_entries : Array[(String, String)],
  dir_entries : Array[(String, String)],
  link_entries : Array[(String, String)],
  cwd : String
) -> Bool {
  if starts_with(cwd, "/home/user") {
    return true
  }

  for i = 0; i < file_entries.length(); i = i + 1 {
    let (path, _value) = file_entries[i]
    if starts_with(path, "/home/user") {
      return true
    }
  }
  for i = 0; i < dir_entries.length(); i = i + 1 {
    let (path, _value) = dir_entries[i]
    if starts_with(path, "/home/user") {
      return true
    }
  }
  for i = 0; i < link_entries.length(); i = i + 1 {
    let (path, _value) = link_entries[i]
    if starts_with(path, "/home/user") {
      return true
    }
  }
  false
}

fn parse_limits(limits_json : String) -> @ast.ExecutionLimits {
  let defaults = @ast.ExecutionLimits::default()
  let mut max_call_depth = defaults.max_call_depth
  let mut max_command_count = defaults.max_command_count
  let mut max_loop_iterations = defaults.max_loop_iterations
  let mut max_string_length = defaults.max_string_length
  let mut max_array_elements = defaults.max_array_elements
  let mut max_heredoc_size = defaults.max_heredoc_size
  let mut max_substitution_depth = defaults.max_substitution_depth
  let mut max_glob_operations = defaults.max_glob_operations
  let mut max_awk_iterations = defaults.max_awk_iterations
  let mut max_sed_iterations = defaults.max_sed_iterations
  let mut max_jq_iterations = defaults.max_jq_iterations

  let entries = parse_json_object(limits_json)
  for i = 0; i < entries.length(); i = i + 1 {
    let (key, value) = entries[i]
    let parsed = parse_decimal_int(value)
    if parsed <= 0 {
      continue
    }
    match key {
      "max_call_depth" => max_call_depth = parsed
      "max_command_count" => max_command_count = parsed
      "max_loop_iterations" => max_loop_iterations = parsed
      "max_string_length" => max_string_length = parsed
      "max_array_elements" => max_array_elements = parsed
      "max_heredoc_size" => max_heredoc_size = parsed
      "max_substitution_depth" => max_substitution_depth = parsed
      "max_glob_operations" => max_glob_operations = parsed
      "max_awk_iterations" => max_awk_iterations = parsed
      "max_sed_iterations" => max_sed_iterations = parsed
      "max_jq_iterations" => max_jq_iterations = parsed
      _ => ()
    }
  }
  {
    max_call_depth,
    max_command_count,
    max_loop_iterations,
    max_string_length,
    max_array_elements,
    max_heredoc_size,
    max_substitution_depth,
    max_glob_operations,
    max_awk_iterations,
    max_sed_iterations,
    max_jq_iterations,
  }
}

/// Ensure parent directories exist for a file path
fn ensure_parents(fs : @fs.InMemoryFs, path : String) -> Unit {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < path.length(); i = i + 1 {
    let ch = path[i].to_int().unsafe_to_char()
    if ch == '/' {
      let s = buf.to_string()
      if s.length() > 0 {
        parts.push(s)
      }
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  // Don't include the last component (that's the file itself)
  // Build parent dirs incrementally
  let dir_buf = StringBuilder::new()
  for i = 0; i < parts.length(); i = i + 1 {
    dir_buf.write_char('/')
    dir_buf.write_string(parts[i])
    let dir_path = dir_buf.to_string()
    if not(fs.exists(dir_path)) {
      try { fs.mkdir(dir_path) } catch { _ => () }
    }
  }
}
