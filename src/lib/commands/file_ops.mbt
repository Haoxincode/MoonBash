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
        if names[j] > names[j + 1] {
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
