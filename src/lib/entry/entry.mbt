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
  let fs = @fs.InMemoryFs::new()

  // Parse and apply files
  let file_entries = parse_json_object(files_json)
  for i = 0; i < file_entries.length(); i = i + 1 {
    let (path, content) = file_entries[i]
    // Ensure parent directories exist
    ensure_parents(fs, path)
    try { fs.write_file(path, content) } catch { _ => () }
  }

  // Parse env vars
  let env : Map[String, String] = {}
  let env_entries = parse_json_object(env_json)
  for i = 0; i < env_entries.length(); i = i + 1 {
    let (key, value) = env_entries[i]
    env[key] = value
  }

  let actual_cwd = if cwd.length() > 0 { cwd } else { "/home/user" }
  let ctx = @interpreter.ExecContext::new(fs, env=env, cwd=actual_cwd)
  let result = ctx.execute(script)
  result_to_json(result)
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
