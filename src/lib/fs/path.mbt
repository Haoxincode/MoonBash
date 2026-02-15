// MoonBash Filesystem Path Utilities

/// Check for null bytes in path
fn validate_path(path : String) -> Unit raise FsError {
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '\u0000' {
      raise FsError("Invalid path: contains null byte")
    }
  }
}

/// Extract substring from start (inclusive) to end (exclusive) using StringBuilder.
fn substr(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

/// Normalize an absolute path: resolve `.`/`..`, collapse slashes, strip trailing slash.
pub fn normalize_path(path : String) -> String raise FsError {
  validate_path(path)
  if path.length() == 0 {
    raise FsError("Invalid path: empty path")
  }
  if path[0] != '/' {
    raise FsError("Invalid path: not absolute: " + path)
  }
  // Split by '/' and process components
  let stack : Array[String] = []
  let mut start = 0
  let len = path.length()
  for i = 0; i <= len; i = i + 1 {
    if i == len || path[i] == '/' {
      if i > start {
        let part = substr(path, start, i)
        if part == "." {
          // skip
        } else if part == ".." {
          if stack.length() > 0 {
            let _ = stack.pop()
          }
        } else {
          stack.push(part)
        }
      }
      start = i + 1
    }
  }
  if stack.length() == 0 {
    return "/"
  }
  let buf = StringBuilder::new()
  for part in stack {
    buf.write_string("/")
    buf.write_string(part)
  }
  buf.to_string()
}

/// Resolve a path relative to a cwd. If path is absolute, normalize it;
/// otherwise join cwd + "/" + path then normalize.
pub fn resolve_path(cwd : String, path : String) -> String raise FsError {
  validate_path(path)
  if path.length() == 0 {
    raise FsError("Invalid path: empty path")
  }
  if path[0] == '/' {
    normalize_path(path)
  } else {
    normalize_path(cwd + "/" + path)
  }
}

/// Get the parent directory of a path.
pub fn parent_path(path : String) -> String {
  if path == "/" {
    return "/"
  }
  let mut last_slash = -1
  for i = path.length() - 1; i >= 0; i = i - 1 {
    if path[i] == '/' {
      last_slash = i
      break
    }
  }
  if last_slash <= 0 {
    "/"
  } else {
    substr(path, 0, last_slash)
  }
}

/// Get the filename component of a path.
pub fn basename(path : String) -> String {
  if path == "/" {
    return "/"
  }
  let mut last_slash = -1
  for i = path.length() - 1; i >= 0; i = i - 1 {
    if path[i] == '/' {
      last_slash = i
      break
    }
  }
  if last_slash < 0 {
    path
  } else {
    substr(path, last_slash + 1, path.length())
  }
}
