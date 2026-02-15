// MoonBash Commands - File Operations
// cat, cp, ls, mkdir, mv, rm, touch

/// cat: concatenate and display file contents
fn cmd_cat(ctx : CommandContext) -> @ast.ExecResult {
  let mut number_lines = false
  let files : Array[String] = []
  for arg in ctx.args {
    if arg == "-n" {
      number_lines = true
    } else {
      files.push(arg)
    }
  }

  if files.length() == 0 {
    // No args = output stdin
    if not(number_lines) {
      return @ast.ExecResult::ok(ctx.stdin_content)
    }
    let out = StringBuilder::new()
    ignore(cmd_cat_write_numbered(out, ctx.stdin_content, 1))
    return @ast.ExecResult::ok(out.to_string())
  }
  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  let mut line_no = 1
  for arg in files {
    if arg == "-" {
      if number_lines {
        line_no = cmd_cat_write_numbered(buf, ctx.stdin_content, line_no)
      } else {
        buf.write_string(ctx.stdin_content)
      }
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
    if number_lines {
      line_no = cmd_cat_write_numbered(buf, content, line_no)
    } else {
      buf.write_string(content)
    }
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

fn cmd_cat_line_prefix(n : Int) -> String {
  let digits = n.to_string()
  let out = StringBuilder::new()
  let pad = 6 - digits.length()
  let mut i = 0
  while i < pad {
    out.write_char(' ')
    i += 1
  }
  out.write_string(digits)
  out.write_char('\t')
  out.to_string()
}

fn cmd_cat_write_numbered(
  out : StringBuilder,
  content : String,
  start_line : Int
) -> Int {
  let line_buf = StringBuilder::new()
  let mut line_no = start_line
  for i = 0; i < content.length(); i = i + 1 {
    let ch = content[i].to_int().unsafe_to_char()
    line_buf.write_char(ch)
    if ch == '\n' {
      out.write_string(cmd_cat_line_prefix(line_no))
      out.write_string(line_buf.to_string())
      line_buf.reset()
      line_no += 1
    }
  }
  if line_buf.to_string().length() > 0 {
    out.write_string(cmd_cat_line_prefix(line_no))
    out.write_string(line_buf.to_string())
    line_no += 1
  }
  line_no
}

/// ls: list directory contents
fn cmd_ls(ctx : CommandContext) -> @ast.ExecResult {
  let mut show_all = false
  let mut almost_all = false
  let mut recursive = false
  let mut reverse = false
  let mut one_per_line = true
  let paths : Array[String] = []

  for arg in ctx.args {
    if arg.length() > 1 && arg[0] == '-' && arg != "--" {
      let mut valid_flags = true
      for i = 1; i < arg.length(); i = i + 1 {
        let flag = arg[i].to_int().unsafe_to_char()
        match flag {
          'a' => {
            show_all = true
            almost_all = false
          }
          'A' => if not(show_all) { almost_all = true }
          'R' => recursive = true
          'r' => reverse = true
          '1' => one_per_line = true
          'l' => () // accepted but not fully formatted in comparison mode
          _ => {
            valid_flags = false
            break
          }
        }
      }
      if not(valid_flags) {
        paths.push(arg)
      }
    } else {
      paths.push(arg)
    }
  }

  if paths.length() == 0 {
    paths.push(".")
  }

  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  let files : Array[(String, String)] = []
  let dirs : Array[(String, String)] = []

  for raw in paths {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, raw)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("ls: \{msg}\n")
        exit_code = 1
        continue
      }
    }

    let stat = try {
      ctx.fs.stat(resolved)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("ls: \{msg}\n")
        exit_code = 1
        continue
      }
    }

    if stat.is_directory {
      dirs.push((raw, resolved))
    } else {
      files.push((raw, resolved))
    }
  }

  for file in files {
    out.write_string(file.0 + "\n")
  }
  if files.length() > 0 && dirs.length() > 0 {
    out.write_char('\n')
  }

  let show_headers = files.length() + dirs.length() > 1
  for idx = 0; idx < dirs.length(); idx = idx + 1 {
    let (label_raw, abs_path) = dirs[idx]
    let label = cmd_ls_display_label(label_raw, abs_path)

    if recursive {
      cmd_ls_list_recursive(
        ctx.fs,
        abs_path,
        label,
        show_all,
        almost_all,
        reverse,
        one_per_line,
        out,
      )
    } else {
      if show_headers {
        out.write_string(label + ":\n")
      }
      let names = cmd_ls_read_names(
        ctx.fs,
        abs_path,
        show_all,
        almost_all,
        reverse,
      )
      cmd_ls_write_names(out, names, one_per_line)
    }

    if idx + 1 < dirs.length() {
      out.write_char('\n')
    }
  }

  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

fn cmd_ls_display_label(raw : String, abs_path : String) -> String {
  if raw == "." || raw.length() == 0 {
    "."
  } else if raw == "/" {
    "/"
  } else if raw[0] == '/' {
    abs_path
  } else {
    cmd_find_trim_trailing_slashes(raw)
  }
}

fn cmd_ls_read_names(
  fs : @fs.InMemoryFs,
  dir_abs : String,
  show_all : Bool,
  almost_all : Bool,
  reverse : Bool
) -> Array[String] {
  let entries = try {
    fs.readdir(dir_abs)
  } catch {
    @fs.FsError(_msg) => return []
  }

  let names : Array[String] = []
  if show_all {
    names.push(".")
    names.push("..")
  }

  for entry in entries {
    let name = entry.name
    if show_all || almost_all {
      names.push(name)
    } else if not(name.length() > 0 && name[0] == '.') {
      names.push(name)
    }
  }

  for i = 0; i < names.length(); i = i + 1 {
    for j = 0; j < names.length() - i - 1; j = j + 1 {
      if cmd_find_compare_ascii(names[j], names[j + 1]) > 0 {
        let tmp = names[j]
        names[j] = names[j + 1]
        names[j + 1] = tmp
      }
    }
  }
  if reverse {
    let mut l = 0
    let mut r = names.length() - 1
    while l < r {
      let tmp = names[l]
      names[l] = names[r]
      names[r] = tmp
      l += 1
      r -= 1
    }
  }
  names
}

fn cmd_ls_write_names(
  out : StringBuilder,
  names : Array[String],
  one_per_line : Bool
) -> Unit {
  if one_per_line {
    for name in names {
      out.write_string(name + "\n")
    }
    return
  }

  let mut first = true
  for name in names {
    if not(first) {
      out.write_string("  ")
    }
    out.write_string(name)
    first = false
  }
  if names.length() > 0 {
    out.write_char('\n')
  }
}

fn cmd_ls_list_recursive(
  fs : @fs.InMemoryFs,
  dir_abs : String,
  label : String,
  show_all : Bool,
  almost_all : Bool,
  reverse : Bool,
  one_per_line : Bool,
  out : StringBuilder
) -> Unit {
  out.write_string(label + ":\n")
  let names = cmd_ls_read_names(fs, dir_abs, show_all, almost_all, reverse)
  cmd_ls_write_names(out, names, one_per_line)

  let subdirs : Array[(String, String)] = []
  let entries = try {
    fs.readdir(dir_abs)
  } catch {
    @fs.FsError(_msg) => return
  }

  let child_names : Array[String] = []
  for entry in entries {
    match entry.entry_type {
      @fs.EntryType::DirectoryType => {
        let name = entry.name
        if not(show_all) && not(almost_all) && name.length() > 0 && name[0] == '.' {
          continue
        }
        child_names.push(name)
      }
      _ => ()
    }
  }
  for i = 0; i < child_names.length(); i = i + 1 {
    for j = 0; j < child_names.length() - i - 1; j = j + 1 {
      if cmd_find_compare_ascii(child_names[j], child_names[j + 1]) > 0 {
        let tmp = child_names[j]
        child_names[j] = child_names[j + 1]
        child_names[j + 1] = tmp
      }
    }
  }
  if reverse {
    let mut l = 0
    let mut r = child_names.length() - 1
    while l < r {
      let tmp = child_names[l]
      child_names[l] = child_names[r]
      child_names[r] = tmp
      l += 1
      r -= 1
    }
  }

  for name in child_names {
    let child_abs = if dir_abs == "/" {
      "/" + name
    } else {
      dir_abs + "/" + name
    }
    let child_label = if label == "." {
      "./" + name
    } else if label == "/" {
      "/" + name
    } else {
      label + "/" + name
    }
    subdirs.push((child_abs, child_label))
  }

  for i = 0; i < subdirs.length(); i = i + 1 {
    out.write_char('\n')
    cmd_ls_list_recursive(
      fs,
      subdirs[i].0,
      subdirs[i].1,
      show_all,
      almost_all,
      reverse,
      one_per_line,
      out,
    )
  }
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
