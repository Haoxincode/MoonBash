// MoonBash Commands - File Operations
// cat, cp, ls, mkdir, mv, rm, touch

/// cat: concatenate and display file contents
fn cmd_cat(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    // No args = output stdin
    return @ast.ExecResult::ok(ctx.stdin_content)
  }
  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for arg in ctx.args {
    if arg == "-" {
      buf.write_string(ctx.stdin_content)
      continue
    }
    let path = try {
      @fs.resolve_path(ctx.cwd, arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("cat: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    let content = try {
      ctx.fs.read_file(path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("cat: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    buf.write_string(content)
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

/// ls: list directory contents
fn cmd_ls(ctx : CommandContext) -> @ast.ExecResult {
  let mut show_all = false
  let mut long_format = false
  let mut one_per_line = false
  let paths : Array[String] = []

  for arg in ctx.args {
    if arg == "-a" {
      show_all = true
    } else if arg == "-l" {
      long_format = true
    } else if arg == "-1" {
      one_per_line = true
    } else if arg == "-la" || arg == "-al" {
      long_format = true
      show_all = true
    } else if arg == "-a1" || arg == "-1a" {
      show_all = true
      one_per_line = true
    } else {
      paths.push(arg)
    }
  }

  if paths.length() == 0 {
    paths.push(ctx.cwd)
  }

  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0

  for path in paths {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("ls: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    let entries = try {
      ctx.fs.readdir(resolved)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("ls: \{msg}\n")
        exit_code = 1
        continue
      }
    }

    // Sort entries alphabetically
    let names : Array[String] = []
    for entry in entries {
      if not(show_all) && entry.name.length() > 0 && entry.name[0] == '.' {
        continue
      }
      names.push(entry.name)
    }
    // Sort
    for i = 0; i < names.length(); i = i + 1 {
      for j = 0; j < names.length() - i - 1; j = j + 1 {
        if names[j + 1] < names[j] {
          let tmp = names[j]
          names[j] = names[j + 1]
          names[j + 1] = tmp
        }
      }
    }

    if long_format {
      for name in names {
        let full_path = if resolved == "/" {
          "/" + name
        } else {
          resolved + "/" + name
        }
        let stat = try {
          ctx.fs.stat(full_path)
        } catch {
          @fs.FsError(_msg) => continue
        }
        let type_char = if stat.is_directory {
          "d"
        } else if stat.is_symlink {
          "l"
        } else {
          "-"
        }
        buf.write_string(
          "\{type_char}rw-r--r-- 1 user user \{stat.size} Jan  1 00:00 \{name}\n",
        )
      }
    } else if one_per_line {
      for name in names {
        buf.write_string(name + "\n")
      }
    } else {
      // Default: space-separated
      let mut first = true
      for name in names {
        if not(first) {
          buf.write_string("  ")
        }
        buf.write_string(name)
        first = false
      }
      if names.length() > 0 {
        buf.write_char('\n')
      }
    }
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

/// mkdir: create directories
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

  let src = try {
    @fs.resolve_path(ctx.cwd, paths[0])
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("cp: \{msg}\n")
  }
  let dst = try {
    @fs.resolve_path(ctx.cwd, paths[1])
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("cp: \{msg}\n")
  }

  try {
    ctx.fs.cp(src, dst, recursive=recursive)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("cp: \{msg}\n")
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

  let src = try {
    @fs.resolve_path(ctx.cwd, paths[0])
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("mv: \{msg}\n")
  }
  let dst = try {
    @fs.resolve_path(ctx.cwd, paths[1])
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("mv: \{msg}\n")
  }

  try {
    ctx.fs.mv(src, dst)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("mv: \{msg}\n")
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
    path.substring(start=0, end=end)
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
    path.substring(start=slash + 1)
  }
}

/// Evaluate a parsed find expression for one entry.
fn cmd_find_matches(
  display_path : String,
  is_file : Bool,
  is_directory : Bool,
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
  for i = 0; i < names.length(); i = i + 1 {
    for j = 0; j < names.length() - i - 1; j = j + 1 {
      if names[j + 1] < names[j] {
        let tmp = names[j]
        names[j] = names[j + 1]
        names[j + 1] = tmp
      }
    }
  }

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
  for i = 0; i < matches.length(); i = i + 1 {
    for j = 0; j < matches.length() - i - 1; j = j + 1 {
      if cmd_find_compare_ascii(matches[j], matches[j + 1]) > 0 {
        let tmp = matches[j]
        matches[j] = matches[j + 1]
        matches[j + 1] = tmp
      }
    }
  }
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
