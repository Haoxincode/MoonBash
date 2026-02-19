// moon_bash Commands - File Operations
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
  let mut long_format = false
  let mut human_readable = false
  let mut sort_size = false
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
          'l' => long_format = true
          'h' => human_readable = true
          'S' => sort_size = true
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
    if long_format {
      let size = cmd_ls_entry_size(ctx.fs, file.1)
      let label = if file.0.length() == 0 { file.1 } else { file.0 }
      out.write_string(cmd_ls_format_size(size, human_readable) + " " + label + "\n")
    } else {
      out.write_string(file.0 + "\n")
    }
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
        sort_size,
        one_per_line,
        long_format,
        human_readable,
        out,
      )
    } else {
      if show_headers {
        out.write_string(label + ":\n")
      }
      let entries = cmd_ls_read_entries(
        ctx.fs,
        abs_path,
        show_all,
        almost_all,
        reverse,
        sort_size,
      )
      if long_format {
        cmd_ls_write_long(out, entries, human_readable)
      } else {
        let names : Array[String] = []
        for entry in entries {
          names.push(entry.0)
        }
        cmd_ls_write_names(out, names, one_per_line)
      }
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

fn cmd_ls_entry_size(fs : @fs.InMemoryFs, abs_path : String) -> Int {
  match fs.entries.get(abs_path) {
    Some(@fs.FsEntry::File(file)) => file.content.length()
    Some(@fs.FsEntry::Directory(_)) => 4096
    Some(@fs.FsEntry::Symlink(link)) => link.target.length()
    None => 0
  }
}

fn cmd_ls_format_human(size : Int, unit : Int, suffix : String) -> String {
  let whole = size / unit
  let rem = size % unit
  if whole < 10 {
    let tenth = (rem * 10) / unit
    whole.to_string() + "." + tenth.to_string() + suffix
  } else {
    whole.to_string() + suffix
  }
}

fn cmd_ls_format_size(size : Int, human_readable : Bool) -> String {
  if not(human_readable) {
    return size.to_string()
  }
  if size >= 1073741824 {
    cmd_ls_format_human(size, 1073741824, "G")
  } else if size >= 1048576 {
    cmd_ls_format_human(size, 1048576, "M")
  } else if size >= 1024 {
    cmd_ls_format_human(size, 1024, "K")
  } else {
    size.to_string()
  }
}

fn cmd_ls_read_entries(
  fs : @fs.InMemoryFs,
  dir_abs : String,
  show_all : Bool,
  almost_all : Bool,
  reverse : Bool,
  sort_size : Bool
) -> Array[(String, Int)] {
  let entries = try {
    fs.readdir(dir_abs)
  } catch {
    @fs.FsError(_msg) => return []
  }

  let names : Array[(String, Int)] = []
  if show_all {
    names.push((".", 4096))
    names.push(("..", 4096))
  }

  for entry in entries {
    let name = entry.name
    if show_all || almost_all || not(name.length() > 0 && name[0] == '.') {
      let child_abs = if dir_abs == "/" {
        "/" + name
      } else {
        dir_abs + "/" + name
      }
      names.push((name, cmd_ls_entry_size(fs, child_abs)))
    }
  }

  names.sort_by(fn(a, b) {
    if sort_size {
      if a.1 > b.1 {
        -1
      } else if a.1 < b.1 {
        1
      } else {
        cmd_find_compare_ascii(a.0, b.0)
      }
    } else {
      cmd_find_compare_ascii(a.0, b.0)
    }
  })
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

fn cmd_ls_write_long(
  out : StringBuilder,
  entries : Array[(String, Int)],
  human_readable : Bool
) -> Unit {
  for entry in entries {
    out.write_string(
      cmd_ls_format_size(entry.1, human_readable) + " " + entry.0 + "\n",
    )
  }
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
  sort_size : Bool,
  one_per_line : Bool,
  long_format : Bool,
  human_readable : Bool,
  out : StringBuilder
) -> Unit {
  out.write_string(label + ":\n")
  let entries = cmd_ls_read_entries(
    fs,
    dir_abs,
    show_all,
    almost_all,
    reverse,
    sort_size,
  )
  if long_format {
    cmd_ls_write_long(out, entries, human_readable)
  } else {
    let names : Array[String] = []
    for entry in entries {
      names.push(entry.0)
    }
    cmd_ls_write_names(out, names, one_per_line)
  }

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
  child_names.sort_by(fn(a, b) {
    if sort_size {
      let a_abs = if dir_abs == "/" { "/" + a } else { dir_abs + "/" + a }
      let b_abs = if dir_abs == "/" { "/" + b } else { dir_abs + "/" + b }
      let a_size = cmd_ls_entry_size(fs, a_abs)
      let b_size = cmd_ls_entry_size(fs, b_abs)
      if a_size > b_size {
        -1
      } else if a_size < b_size {
        1
      } else {
        cmd_find_compare_ascii(a, b)
      }
    } else {
      cmd_find_compare_ascii(a, b)
    }
  })
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
      sort_size,
      one_per_line,
      long_format,
      human_readable,
      out,
    )
  }
}

