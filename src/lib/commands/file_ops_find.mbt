// moon_bash Commands - mkdir, rm, cp, mv, touch, find

fn cmd_mkdir(ctx : CommandContext) -> @ast.ExecResult {
  let mut recursive = false
  let paths : Array[String] = []

  for arg in ctx.args {
    if arg == "-p" {
      recursive = true
    } else {
      paths.push(arg)
    }
  }

  if paths.length() == 0 {
    return @ast.ExecResult::err("mkdir: missing operand\n")
  }

  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for path in paths {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("mkdir: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    try {
      ctx.fs.mkdir(resolved, recursive=recursive)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("mkdir: \{msg}\n")
        exit_code = 1
      }
    }
  }
  @ast.ExecResult::new(stderr=errbuf.to_string(), exit_code=exit_code)
}

/// rm: remove files or directories
fn cmd_rm(ctx : CommandContext) -> @ast.ExecResult {
  let mut recursive = false
  let mut force = false
  let paths : Array[String] = []

  for arg in ctx.args {
    match arg {
      "-r" | "-R" => recursive = true
      "-f" => force = true
      "-rf" | "-fr" | "-Rf" | "-fR" => { recursive = true; force = true }
      _ => paths.push(arg)
    }
  }

  if paths.length() == 0 && not(force) {
    return @ast.ExecResult::err("rm: missing operand\n")
  }

  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for path in paths {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("rm: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    try {
      ctx.fs.rm(resolved, recursive=recursive, force=force)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("rm: \{msg}\n")
        exit_code = 1
      }
    }
  }
  @ast.ExecResult::new(stderr=errbuf.to_string(), exit_code=exit_code)
}

/// cp: copy files or directories
fn cmd_cp(ctx : CommandContext) -> @ast.ExecResult {
  let mut recursive = false
  let paths : Array[String] = []

  for arg in ctx.args {
    match arg {
      "-r" | "-R" | "-a" => recursive = true
      _ => paths.push(arg)
    }
  }

  if paths.length() < 2 {
    return @ast.ExecResult::err("cp: missing operand\n")
  }

  let dst = try {
    @fs.resolve_path(ctx.cwd, paths[paths.length() - 1])
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("cp: \{msg}\n")
  }

  if paths.length() > 2 {
    let dst_is_dir = try {
      let stat = ctx.fs.stat(dst)
      stat.is_directory
    } catch {
      @fs.FsError(_msg) => false
    }
    if not(dst_is_dir) {
      return @ast.ExecResult::err("cp: target '\{paths[paths.length() - 1]}' is not a directory\n")
    }
  }

  for i = 0; i < paths.length() - 1; i = i + 1 {
    let src = try {
      @fs.resolve_path(ctx.cwd, paths[i])
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("cp: \{msg}\n")
    }
    try {
      ctx.fs.cp(src, dst, recursive=recursive)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("cp: \{msg}\n")
    }
  }
  @ast.ExecResult::new()
}

/// mv: move/rename files or directories
fn cmd_mv(ctx : CommandContext) -> @ast.ExecResult {
  let paths : Array[String] = []
  for arg in ctx.args {
    paths.push(arg)
  }

  if paths.length() < 2 {
    return @ast.ExecResult::err("mv: missing operand\n")
  }

  let dst = try {
    @fs.resolve_path(ctx.cwd, paths[paths.length() - 1])
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("mv: \{msg}\n")
  }

  if paths.length() > 2 {
    let dst_is_dir = try {
      let stat = ctx.fs.stat(dst)
      stat.is_directory
    } catch {
      @fs.FsError(_msg) => false
    }
    if not(dst_is_dir) {
      return @ast.ExecResult::err("mv: target '\{paths[paths.length() - 1]}' is not a directory\n")
    }
  }

  for i = 0; i < paths.length() - 1; i = i + 1 {
    let src = try {
      @fs.resolve_path(ctx.cwd, paths[i])
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("mv: \{msg}\n")
    }
    try {
      ctx.fs.mv(src, dst)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("mv: \{msg}\n")
    }
  }
  @ast.ExecResult::new()
}

/// touch: create empty files or update timestamps
fn cmd_touch(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    return @ast.ExecResult::err("touch: missing file operand\n")
  }

  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for arg in ctx.args {
    let path = try {
      @fs.resolve_path(ctx.cwd, arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("touch: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    if not(ctx.fs.exists(path)) {
      try {
        ctx.fs.write_file(path, "")
      } catch {
        @fs.FsError(msg) => {
          errbuf.write_string("touch: \{msg}\n")
          exit_code = 1
        }
      }
    }
    // If file exists, we'd update mtime - but our mtime is always 0
  }
  @ast.ExecResult::new(stderr=errbuf.to_string(), exit_code=exit_code)
}

/// Parse integer from string with optional sign.
fn cmd_find_parse_int(s : String) -> Int {
  let mut result = 0
  let mut neg = false
  let mut start = 0
  if s.length() > 0 && s[0] == '-' {
    neg = true
    start = 1
  } else if s.length() > 0 && s[0] == '+' {
    start = 1
  }
  for i = start; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      break
    }
  }
  if neg { -result } else { result }
}

/// Trim trailing slashes (except for root and ".").
fn cmd_find_trim_trailing_slashes(path : String) -> String {
  if path == "/" || path == "." {
    return path
  }
  let mut end = path.length()
  while end > 1 && path[end - 1] == '/' {
    end -= 1
  }
  if end == path.length() {
    path
  } else {
    path.view(start_offset=0, end_offset=end).to_string()
  }
}

/// Join display path with child name.
fn cmd_find_join_display(base : String, name : String) -> String {
  if base == "/" {
    "/" + name
  } else {
    base + "/" + name
  }
}

/// Basename logic for displayed path.
fn cmd_find_display_basename(path : String) -> String {
  if path == "." || path == "/" {
    return path
  }
  let mut slash = -1
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      slash = i
    }
  }
  if slash < 0 {
    path
  } else if slash + 1 >= path.length() {
    ""
  } else {
    path.view(start_offset=slash + 1).to_string()
  }
}

fn cmd_find_parse_octal(s : String) -> Int {
  let mut value = 0
  let mut i = 0
  if s.length() >= 2 &&
    s[0].to_int().unsafe_to_char() == '0' &&
    (s[1].to_int().unsafe_to_char() == 'o' || s[1].to_int().unsafe_to_char() == 'O') {
    i = 2
  }
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '7' {
      break
    }
    value = value * 8 + (ch.to_int() - '0'.to_int())
    i += 1
  }
  value
}

fn cmd_find_perm_matches(expr : String, mode : Int) -> Bool {
  if expr.length() == 0 {
    return false
  }
  let first = expr[0].to_int().unsafe_to_char()
  if first == '-' {
    let mask = cmd_find_parse_octal(expr.view(start_offset=1).to_string())
    mode.land(mask) == mask
  } else if first == '/' {
    let mask = cmd_find_parse_octal(expr.view(start_offset=1).to_string())
    mode.land(mask) != 0
  } else {
    let expected = cmd_find_parse_octal(expr)
    mode.land(0o7777) == expected
  }
}

/// Evaluate a parsed find expression for one entry.
fn cmd_find_matches(
  display_path : String,
  is_file : Bool,
  is_directory : Bool,
  mode : Int,
  groups : Array[Array[(String, String)]],
  has_predicates : Bool
) -> Bool {
  if not(has_predicates) {
    return true
  }
  let base = cmd_find_display_basename(display_path)
  for group in groups {
    let mut group_match = true
    for pred in group {
      let (kind, value) = pred
      if kind == "name" {
        if not(@fs.glob_match(value, base)) {
          group_match = false
          break
        }
      } else if kind == "type" {
        if value == "f" {
          if not(is_file) {
            group_match = false
            break
          }
        } else if value == "d" {
          if not(is_directory) {
            group_match = false
            break
          }
        } else {
          group_match = false
          break
        }
      } else if kind == "perm" {
        if not(cmd_find_perm_matches(value, mode)) {
          group_match = false
          break
        }
      }
    }
    if group_match {
      return true
    }
  }
  false
}

/// Recursively walk from start path and collect matching entries.
fn cmd_find_walk(
  fs : @fs.InMemoryFs,
  abs_path : String,
  display_path : String,
  depth : Int,
  mindepth : Int,
  maxdepth : Int?,
  groups : Array[Array[(String, String)]],
  has_predicates : Bool,
  matches : Array[String]
) -> Unit {
  match maxdepth {
    Some(maxd) => {
      if depth > maxd {
        return
      }
    }
    None => ()
  }

  let stat = try {
    fs.stat(abs_path)
  } catch {
    @fs.FsError(_msg) => return
  }

  if depth >= mindepth &&
    cmd_find_matches(
      display_path,
      stat.is_file,
      stat.is_directory,
      stat.mode,
      groups,
      has_predicates,
    ) {
    matches.push(display_path)
  }

  if not(stat.is_directory) {
    return
  }

  let should_descend = match maxdepth {
    Some(maxd) => depth < maxd
    None => true
  }
  if not(should_descend) {
    return
  }

  let entries = try {
    fs.readdir(abs_path)
  } catch {
    @fs.FsError(_msg) => return
  }

  let names : Array[String] = []
  for entry in entries {
    names.push(entry.name)
  }
  // Keep deterministic output order.
  names.sort_by(fn(a, b) {
    cmd_find_compare_ascii(a, b)
  })

  for name in names {
    let child_abs = if abs_path == "/" {
      "/" + name
    } else {
      abs_path + "/" + name
    }
    let child_display = cmd_find_join_display(display_path, name)
    cmd_find_walk(
      fs,
      child_abs,
      child_display,
      depth + 1,
      mindepth,
      maxdepth,
      groups,
      has_predicates,
      matches,
    )
  }
}

/// ASCII byte-wise string compare for deterministic ordering.
fn cmd_find_compare_ascii(a : String, b : String) -> Int {
  let min_len = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < min_len; i = i + 1 {
    if a[i] < b[i] {
      return -1
    }
    if a[i] > b[i] {
      return 1
    }
  }
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    0
  }
}

/// find: recursively search paths with minimal predicate support.
fn cmd_find(ctx : CommandContext) -> @ast.ExecResult {
  let start_paths : Array[String] = []
  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-o" || arg.has_prefix("-") {
      break
    }
    start_paths.push(arg)
    i += 1
  }
  if start_paths.length() == 0 {
    start_paths.push(".")
  }

  let groups : Array[Array[(String, String)]] = []
  let mut current_group : Array[(String, String)] = []
  let mut has_predicates = false
  let mut maxdepth : Int? = None
  let mut mindepth = 0

  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-o" {
      groups.push(current_group)
      current_group = []
      i += 1
      continue
    }
    if arg == "-name" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("find: missing argument to -name\n")
      }
      current_group.push(("name", ctx.args[i + 1]))
      has_predicates = true
      i += 2
      continue
    }
    if arg == "-type" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("find: missing argument to -type\n")
      }
      current_group.push(("type", ctx.args[i + 1]))
      has_predicates = true
      i += 2
      continue
    }
    if arg == "-perm" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("find: missing argument to -perm\n")
      }
      current_group.push(("perm", ctx.args[i + 1]))
      has_predicates = true
      i += 2
      continue
    }
    if arg == "-maxdepth" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("find: missing argument to -maxdepth\n")
      }
      maxdepth = Some(cmd_find_parse_int(ctx.args[i + 1]))
      i += 2
      continue
    }
    if arg == "-mindepth" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("find: missing argument to -mindepth\n")
      }
      mindepth = cmd_find_parse_int(ctx.args[i + 1])
      i += 2
      continue
    }
    return @ast.ExecResult::err("find: unsupported predicate: \{arg}\n")
  }
  groups.push(current_group)

  let matches : Array[String] = []
  let errbuf = StringBuilder::new()
  let mut exit_code = 0

  for start_arg in start_paths {
    let start_abs = try {
      @fs.resolve_path(ctx.cwd, start_arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("find: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    let start_display = if start_arg.length() == 0 || start_arg == "." {
      "."
    } else if start_arg[0] == '/' {
      start_abs
    } else {
      cmd_find_trim_trailing_slashes(start_arg)
    }
    cmd_find_walk(
      ctx.fs,
      start_abs,
      start_display,
      0,
      mindepth,
      maxdepth,
      groups,
      has_predicates,
      matches,
    )
  }

  // Keep deterministic output even before external `sort`.
  matches.sort_by(fn(a, b) {
    cmd_find_compare_ascii(a, b)
  })
  let out = StringBuilder::new()
  for m in matches {
    out.write_string(m + "\n")
  }

  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}
