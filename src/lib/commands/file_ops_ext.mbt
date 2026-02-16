// moon_bash Commands - Extended File Operations
// rmdir, stat, file, tree, du, chmod, ln, readlink

/// rmdir: remove empty directories
fn cmd_rmdir(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    return @ast.ExecResult::err("rmdir: missing operand\n")
  }
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for arg in ctx.args {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("rmdir: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    match ctx.fs.entries.get(resolved) {
      None => {
        errbuf.write_string("rmdir: failed to remove '\{arg}': No such file or directory\n")
        exit_code = 1
      }
      Some(@fs.FsEntry::File(_)) | Some(@fs.FsEntry::Symlink(_)) => {
        errbuf.write_string("rmdir: failed to remove '\{arg}': Not a directory\n")
        exit_code = 1
      }
      Some(@fs.FsEntry::Directory(_)) => {
        // Check if directory has children
        let prefix = if resolved == "/" { "/" } else { resolved + "/" }
        let mut has_children = false
        ctx.fs.entries.each(fn(key, _value) {
          if key.length() > prefix.length() && key.has_prefix(prefix) {
            has_children = true
          }
        })
        if has_children {
          errbuf.write_string("rmdir: failed to remove '\{arg}': Directory not empty\n")
          exit_code = 1
        } else {
          ctx.fs.entries.remove(resolved)
        }
      }
    }
  }
  @ast.ExecResult::new(stderr=errbuf.to_string(), exit_code=exit_code)
}

/// Format octal mode as permission string like -rw-r--r--
fn format_mode_string(mode : Int, is_dir : Bool, is_link : Bool) -> String {
  let buf = StringBuilder::new()
  if is_dir {
    buf.write_char('d')
  } else if is_link {
    buf.write_char('l')
  } else {
    buf.write_char('-')
  }
  // Owner
  buf.write_char(if mode.land(0o400) != 0 { 'r' } else { '-' })
  buf.write_char(if mode.land(0o200) != 0 { 'w' } else { '-' })
  buf.write_char(if mode.land(0o100) != 0 { 'x' } else { '-' })
  // Group
  buf.write_char(if mode.land(0o040) != 0 { 'r' } else { '-' })
  buf.write_char(if mode.land(0o020) != 0 { 'w' } else { '-' })
  buf.write_char(if mode.land(0o010) != 0 { 'x' } else { '-' })
  // Other
  buf.write_char(if mode.land(0o004) != 0 { 'r' } else { '-' })
  buf.write_char(if mode.land(0o002) != 0 { 'w' } else { '-' })
  buf.write_char(if mode.land(0o001) != 0 { 'x' } else { '-' })
  buf.to_string()
}

/// Format an octal mode as a 4-digit zero-padded string
fn format_octal(mode : Int) -> String {
  let d3 = mode / 512 // 0o1000
  let rem3 = mode % 512
  let d2 = rem3 / 64  // 0o100
  let rem2 = rem3 % 64
  let d1 = rem2 / 8   // 0o10
  let d0 = rem2 % 8
  d3.to_string() + d2.to_string() + d1.to_string() + d0.to_string()
}

/// stat: display file status
fn cmd_stat(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    return @ast.ExecResult::err("stat: missing operand\n")
  }
  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for arg in ctx.args {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("stat: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    let stat = try {
      ctx.fs.stat(resolved)
    } catch {
      @fs.FsError(_msg) => {
        errbuf.write_string("stat: cannot stat '\{arg}': No such file or directory\n")
        exit_code = 1
        continue
      }
    }
    let type_str = if stat.is_directory {
      "directory"
    } else if stat.is_symlink {
      "symbolic link"
    } else {
      "regular file"
    }
    let size = if stat.is_directory { 4096 } else { stat.size }
    let mode_str = format_mode_string(stat.mode, stat.is_directory, stat.is_symlink)
    let octal_str = format_octal(stat.mode)
    out.write_string("  File: \{arg}\n")
    out.write_string("  Size: \{size}\tType: \{type_str}\n")
    out.write_string("Access: (\{octal_str}/\{mode_str})\n")
    out.write_string("Modify: 1970-01-01 00:00:00.000000000 +0000\n")
  }
  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

/// file: determine file type
fn cmd_file(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    return @ast.ExecResult::err("file: missing operand\n")
  }
  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for arg in ctx.args {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("file: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    match ctx.fs.entries.get(resolved) {
      None => {
        errbuf.write_string("file: \{arg}: No such file or directory\n")
        exit_code = 1
      }
      Some(@fs.FsEntry::Directory(_)) => {
        out.write_string("\{arg}: directory\n")
      }
      Some(@fs.FsEntry::Symlink(data)) => {
        out.write_string("\{arg}: symbolic link to \{data.target}\n")
      }
      Some(@fs.FsEntry::File(data)) => {
        let content = data.content
        let ftype = if content.length() == 0 {
          "empty"
        } else if content.length() >= 2 && content[0] == '#' && content[1] == '!' {
          "script"
        } else if content[0] == '{' || content[0] == '[' {
          "JSON data"
        } else {
          "ASCII text"
        }
        out.write_string("\{arg}: \{ftype}\n")
      }
    }
  }
  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

/// tree: recursive directory listing with box-drawing characters
fn cmd_tree(ctx : CommandContext) -> @ast.ExecResult {
  let path = if ctx.args.length() > 0 { ctx.args[0] } else { "." }
  let resolved = try {
    @fs.resolve_path(ctx.cwd, path)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("tree: \{msg}\n")
  }
  match ctx.fs.entries.get(resolved) {
    None => return @ast.ExecResult::err("tree: '\{path}': No such file or directory\n")
    Some(@fs.FsEntry::File(_)) | Some(@fs.FsEntry::Symlink(_)) =>
      return @ast.ExecResult::err("tree: '\{path}': Not a directory\n")
    _ => ()
  }
  let out = StringBuilder::new()
  out.write_string(path + "\n")
  let mut dir_count = 0
  let mut file_count = 0
  cmd_tree_walk(ctx.fs, resolved, "", out, fn(_is_dir) {
    if _is_dir {
      dir_count += 1
    } else {
      file_count += 1
    }
  })
  out.write_string("\n\{dir_count} directories, \{file_count} files\n")
  @ast.ExecResult::ok(out.to_string())
}

/// Recursive helper for tree command
fn cmd_tree_walk(
  fs : @fs.InMemoryFs,
  abs_path : String,
  prefix : String,
  out : StringBuilder,
  counter : (Bool) -> Unit
) -> Unit {
  let entries = try {
    fs.readdir(abs_path)
  } catch {
    @fs.FsError(_msg) => return
  }
  // Collect and sort names
  let items : Array[(String, Bool)] = []
  for entry in entries {
    let is_dir = match entry.entry_type {
      @fs.EntryType::DirectoryType => true
      _ => false
    }
    items.push((entry.name, is_dir))
  }
  items.sort_by(fn(a, b) {
    cmd_find_compare_ascii(a.0, b.0)
  })
  for i = 0; i < items.length(); i = i + 1 {
    let (name, is_dir) = items[i]
    let is_last = i == items.length() - 1
    let connector = if is_last { "\u{2514}\u{2500}\u{2500} " } else { "\u{251C}\u{2500}\u{2500} " }
    out.write_string(prefix + connector + name + "\n")
    counter(is_dir)
    if is_dir {
      let child_abs = if abs_path == "/" {
        "/" + name
      } else {
        abs_path + "/" + name
      }
      let child_prefix = if is_last {
        prefix + "    "
      } else {
        prefix + "\u{2502}   "
      }
      cmd_tree_walk(fs, child_abs, child_prefix, out, counter)
    }
  }
}

/// Format size in human-readable format (K, M, G)
fn format_human_size(size : Int) -> String {
  if size >= 1073741824 {
    let g = size / 1073741824
    g.to_string() + "G"
  } else if size >= 1048576 {
    let m = size / 1048576
    m.to_string() + "M"
  } else if size >= 1024 {
    let k = size / 1024
    k.to_string() + "K"
  } else {
    size.to_string()
  }
}

/// du: disk usage
fn cmd_du(ctx : CommandContext) -> @ast.ExecResult {
  let mut summary_only = false
  let mut human_readable = false
  let mut all_entries = false
  let mut max_depth : Int? = None
  let paths : Array[String] = []

  let mut stop_options = false
  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if stop_options {
      paths.push(arg)
      i += 1
      continue
    }

    if arg == "--" {
      stop_options = true
      i += 1
      continue
    }
    if arg == "--max-depth" && i + 1 < ctx.args.length() {
      max_depth = Some(cmd_find_parse_int(ctx.args[i + 1]))
      i += 2
      continue
    }
    if arg.has_prefix("--max-depth=") {
      max_depth = Some(cmd_find_parse_int(arg.substring(start=12)))
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      let mut valid_flags = true
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          's' => summary_only = true
          'h' => human_readable = true
          'a' => all_entries = true
          _ => {
            valid_flags = false
            break
          }
        }
      }
      if valid_flags {
        i += 1
        continue
      }
    }
    paths.push(arg)
    i += 1
  }

  ignore(all_entries)
  if paths.length() == 0 {
    paths.push(".")
  }
  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for path in paths {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("du: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    if not(ctx.fs.entries.contains(resolved)) {
      errbuf.write_string("du: cannot access '\{path}': No such file or directory\n")
      exit_code = 1
      continue
    }
    // Collect all paths and their sizes under resolved
    let prefix = if resolved == "/" { "/" } else { resolved + "/" }
    let sub_entries : Array[(String, Int)] = []
    let mut total = 0
    ctx.fs.entries.each(fn(key, value) {
      if key == resolved || key.has_prefix(prefix) {
        let size = match value {
          @fs.FsEntry::File(data) => data.content.length()
          @fs.FsEntry::Directory(_) => 4096
          @fs.FsEntry::Symlink(data) => data.target.length()
        }
        let rel_depth = if key == resolved {
          0
        } else {
          cmd_du_relative_depth(key.substring(start=resolved.length()))
        }
        let include_entry = match max_depth {
          Some(limit) => rel_depth <= limit
          None => true
        }
        if include_entry {
          total += size
          // Compute display path relative to the argument
          let display = if key == resolved {
            path
          } else {
            let rel = key.substring(start=resolved.length())
            if path == "." {
              "." + rel
            } else {
              path + rel
            }
          }
          sub_entries.push((display, size))
        }
      }
    })
    if summary_only {
      let size_str = if human_readable { format_human_size(total) } else { total.to_string() }
      out.write_string(size_str + "\t" + path + "\n")
    } else {
      // Sort entries for deterministic output
      sub_entries.sort_by(fn(a, b) {
        cmd_find_compare_ascii(a.0, b.0)
      })
      for entry in sub_entries {
        let size_str = if human_readable { format_human_size(entry.1) } else { entry.1.to_string() }
        out.write_string(size_str + "\t" + entry.0 + "\n")
      }
    }
  }
  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

fn cmd_du_relative_depth(rel : String) -> Int {
  let mut depth = 0
  let mut in_segment = false
  for i = 0; i < rel.length(); i = i + 1 {
    let ch = rel[i].to_int().unsafe_to_char()
    if ch == '/' {
      if in_segment {
        depth += 1
        in_segment = false
      }
    } else {
      in_segment = true
    }
  }
  if in_segment {
    depth += 1
  }
  depth
}

/// Parse an octal string to integer
fn parse_octal(s : String) -> Int {
  let mut result = 0
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '7' {
      result = result * 8 + (ch.to_int() - '0'.to_int())
    } else {
      break
    }
  }
  result
}

/// chmod: change file mode
fn cmd_chmod(ctx : CommandContext) -> @ast.ExecResult {
  let mut recursive = false
  let args : Array[String] = []
  for arg in ctx.args {
    if arg == "-R" || arg == "-r" {
      recursive = true
    } else {
      args.push(arg)
    }
  }
  if args.length() < 2 {
    return @ast.ExecResult::err("chmod: missing operand\n")
  }
  let mode_str = args[0]
  let mode = parse_octal(mode_str)
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for i = 1; i < args.length(); i = i + 1 {
    let path = args[i]
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("chmod: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    if not(ctx.fs.entries.contains(resolved)) {
      errbuf.write_string("chmod: cannot access '\{path}': No such file or directory\n")
      exit_code = 1
      continue
    }
    try {
      ctx.fs.chmod(resolved, mode)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("chmod: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    if recursive {
      let prefix = resolved + "/"
      let child_paths : Array[String] = []
      ctx.fs.entries.each(fn(key, _value) {
        if key.has_prefix(prefix) {
          child_paths.push(key)
        }
      })
      for child_path in child_paths {
        try {
          ctx.fs.chmod(child_path, mode)
        } catch {
          @fs.FsError(msg) => {
            errbuf.write_string("chmod: \{msg}\n")
            exit_code = 1
          }
        }
      }
    }
  }
  @ast.ExecResult::new(stderr=errbuf.to_string(), exit_code=exit_code)
}

/// ln: create links
fn cmd_ln(ctx : CommandContext) -> @ast.ExecResult {
  let mut symbolic = false
  let args : Array[String] = []
  for arg in ctx.args {
    match arg {
      "-s" => symbolic = true
      "-sf" | "-fs" => symbolic = true
      _ => args.push(arg)
    }
  }
  // VFS only supports symlinks
  if not(symbolic) {
    return @ast.ExecResult::err("ln: hard links not supported in sandbox\n")
  }
  if args.length() < 2 {
    return @ast.ExecResult::err("ln: missing operand\n")
  }
  let target = args[0]
  let link_name = args[1]
  let link_resolved = try {
    @fs.resolve_path(ctx.cwd, link_name)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("ln: \{msg}\n")
  }
  try {
    ctx.fs.symlink(target, link_resolved)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("ln: \{msg}\n")
  }
  @ast.ExecResult::new()
}

/// readlink: read symbolic link target
fn cmd_readlink(ctx : CommandContext) -> @ast.ExecResult {
  let mut canonicalize = false
  let paths : Array[String] = []
  for arg in ctx.args {
    match arg {
      "-f" | "-e" | "-m" => canonicalize = true
      _ => paths.push(arg)
    }
  }
  if paths.length() == 0 {
    return @ast.ExecResult::err("readlink: missing operand\n")
  }
  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for path in paths {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("readlink: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    if canonicalize {
      // Follow all symlinks to get final target
      let mut current = resolved
      let mut depth = 0
      let max_depth = 40
      let mut err_found = false
      while depth < max_depth {
        let stat = try {
          ctx.fs.stat(current)
        } catch {
          @fs.FsError(msg) => {
            errbuf.write_string("readlink: \{msg}\n")
            exit_code = 1
            err_found = true
            break
          }
        }
        if stat.is_symlink {
          let link_target = try {
            ctx.fs.readlink(current)
          } catch {
            @fs.FsError(msg) => {
              errbuf.write_string("readlink: \{msg}\n")
              exit_code = 1
              err_found = true
              break
            }
          }
          current = try {
            if link_target.length() > 0 && link_target[0] == '/' {
              @fs.resolve_path("/", link_target)
            } else {
              @fs.resolve_path(@fs.parent_path(current), link_target)
            }
          } catch {
            @fs.FsError(msg) => {
              errbuf.write_string("readlink: \{msg}\n")
              exit_code = 1
              err_found = true
              break
            }
          }
          depth += 1
        } else {
          break
        }
      }
      if not(err_found) {
        out.write_string(current + "\n")
      }
    } else {
      let target = try {
        ctx.fs.readlink(resolved)
      } catch {
        @fs.FsError(msg) => {
          errbuf.write_string("readlink: \{msg}\n")
          exit_code = 1
          continue
        }
      }
      out.write_string(target + "\n")
    }
  }
  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}
