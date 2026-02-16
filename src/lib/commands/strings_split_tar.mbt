// MoonBash Commands - strings / split / tar

priv struct TarEntry {
  path : String
  is_dir : Bool
  content : String
}

// ============================================================================
// Common Helpers
// ============================================================================

fn cst_parse_int(s : String) -> Int {
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

fn cst_substr(s : String, start : Int, end_ : Int) -> String {
  let mut start = start
  let mut end_ = end_
  if start < 0 {
    start = 0
  }
  if end_ > s.length() {
    end_ = s.length()
  }
  if start >= end_ {
    return ""
  }
  let out = StringBuilder::new()
  for i = start; i < end_; i = i + 1 {
    out.write_char(s[i].to_int().unsafe_to_char())
  }
  out.to_string()
}

fn cst_split_path(path : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  for i = 0; i <= path.length(); i = i + 1 {
    if i == path.length() || path[i] == '/' {
      if i > start {
        parts.push(path.substring(start=start, end=i))
      }
      start = i + 1
    }
  }
  parts
}

fn cst_join_path(parts : Array[String], start_idx : Int) -> String {
  let out = StringBuilder::new()
  for i = start_idx; i < parts.length(); i = i + 1 {
    if i > start_idx {
      out.write_char('/')
    }
    out.write_string(parts[i])
  }
  out.to_string()
}

fn cst_sort_strings(values : Array[String]) -> Unit {
  values.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
}

fn cst_starts_with(s : String, prefix : String) -> Bool {
  if prefix.length() > s.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

fn cst_read_input(
  ctx : CommandContext,
  input_file : String?
) -> String raise @fs.FsError {
  match input_file {
    Some(path) => {
      if path == "-" {
        return ctx.stdin_content
      }
      let resolved = @fs.resolve_path(ctx.cwd, path)
      ctx.fs.read_file(resolved)
    }
    None => ctx.stdin_content
  }
}

// ============================================================================
// strings
// ============================================================================

fn cmd_strings_collect(content : String, min_len : Int, out : StringBuilder) -> Unit {
  let normalized = decode_strings_escapes(content)
  let buf = StringBuilder::new()
  let flush = () => {
    let s = buf.to_string()
    if s.length() >= min_len {
      out.write_string(s)
      out.write_char('\n')
    }
    buf.reset()
  }

  for i = 0; i < normalized.length(); i = i + 1 {
    let ch = normalized[i].to_int().unsafe_to_char()
    if ch >= ' ' && ch <= '~' {
      buf.write_char(ch)
    } else {
      flush()
    }
  }
  flush()
}

fn decode_strings_escapes(s : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < s.length() {
      let next = s[i + 1].to_int().unsafe_to_char()
      if next == 'x' && i + 3 < s.length() &&
        is_hex_char(s[i + 2].to_int().unsafe_to_char()) &&
        is_hex_char(s[i + 3].to_int().unsafe_to_char()) {
        let code = hex_value(s[i + 2].to_int().unsafe_to_char()) * 16 +
          hex_value(s[i + 3].to_int().unsafe_to_char())
        out.write_char(code.unsafe_to_char())
        i += 4
        continue
      }
      if next == 'u' && i + 5 < s.length() {
        let mut ok = true
        let mut value = 0
        for j = i + 2; j <= i + 5; j = j + 1 {
          let hc = s[j].to_int().unsafe_to_char()
          if not(is_hex_char(hc)) {
            ok = false
            break
          }
          value = value * 16 + hex_value(hc)
        }
        if ok {
          out.write_char(value.unsafe_to_char())
          i += 6
          continue
        }
      }
      if next == '0' {
        out.write_char('\u0000')
        i += 2
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn is_hex_char(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'a' && ch <= 'f') ||
  (ch >= 'A' && ch <= 'F')
}

fn hex_value(ch : Char) -> Int {
  if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if ch >= 'a' && ch <= 'f' {
    10 + ch.to_int() - 'a'.to_int()
  } else if ch >= 'A' && ch <= 'F' {
    10 + ch.to_int() - 'A'.to_int()
  } else {
    0
  }
}

fn cmd_strings(ctx : CommandContext) -> @ast.ExecResult {
  let mut min_len = 4
  let files : Array[String] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-n" && i + 1 < ctx.args.length() {
      min_len = cst_parse_int(ctx.args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-n") && arg.length() > 2 {
      min_len = cst_parse_int(arg.substring(start=2))
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }
  if min_len < 1 {
    min_len = 1
  }

  let out = StringBuilder::new()
  if files.length() == 0 {
    cmd_strings_collect(ctx.stdin_content, min_len, out)
    return @ast.ExecResult::ok(out.to_string())
  }

  for file in files {
    let content = try {
      let resolved = @fs.resolve_path(ctx.cwd, file)
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("strings: \{msg}\n")
    }
    cmd_strings_collect(content, min_len, out)
  }

  @ast.ExecResult::ok(out.to_string())
}

// ============================================================================
// split
// ============================================================================

fn cmd_split_suffix(index : Int) -> String {
  let alphabet = "abcdefghijklmnopqrstuvwxyz"
  let n = if index < 0 { 0 } else { index }
  let first = (n / 26) % 26
  let second = n % 26
  let out = StringBuilder::new()
  out.write_char(alphabet[first].to_int().unsafe_to_char())
  out.write_char(alphabet[second].to_int().unsafe_to_char())
  out.to_string()
}

fn cmd_split_lines_preserve(input : String) -> Array[String] {
  let lines : Array[String] = []
  let line = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    line.write_char(ch)
    if ch == '\n' {
      lines.push(line.to_string())
      line.reset()
    }
  }
  let trailing = line.to_string()
  if trailing.length() > 0 {
    lines.push(trailing)
  }
  lines
}

fn cmd_split_write_chunks(
  ctx : CommandContext,
  chunks : Array[String],
  prefix : String
) -> @ast.ExecResult {
  for i = 0; i < chunks.length(); i = i + 1 {
    let name = prefix + cmd_split_suffix(i)
    let path = try {
      @fs.resolve_path(ctx.cwd, name)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("split: \{msg}\n")
    }
    try {
      ctx.fs.write_file(path, chunks[i])
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("split: \{msg}\n")
    }
  }
  @ast.ExecResult::ok("")
}

fn cmd_split(ctx : CommandContext) -> @ast.ExecResult {
  let mut lines_per_chunk = 1000
  let mut bytes_per_chunk : Int? = None
  let positionals : Array[String] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-l" && i + 1 < ctx.args.length() {
      lines_per_chunk = cst_parse_int(ctx.args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-l") && arg.length() > 2 {
      lines_per_chunk = cst_parse_int(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-b" && i + 1 < ctx.args.length() {
      bytes_per_chunk = Some(cst_parse_int(ctx.args[i + 1]))
      i += 2
      continue
    }
    if arg.has_prefix("-b") && arg.length() > 2 {
      bytes_per_chunk = Some(cst_parse_int(arg.substring(start=2)))
      i += 1
      continue
    }
    positionals.push(arg)
    i += 1
  }

  if lines_per_chunk <= 0 {
    lines_per_chunk = 1
  }

  let input_file : String? = if positionals.length() >= 1 {
    Some(positionals[0])
  } else {
    None
  }
  let prefix = if positionals.length() >= 2 { positionals[1] } else { "x" }

  let input = try {
    cst_read_input(ctx, input_file)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("split: \{msg}\n")
  }
  if input.length() == 0 {
    return @ast.ExecResult::ok("")
  }

  let chunks : Array[String] = []
  match bytes_per_chunk {
    Some(size) => {
      let chunk_size = if size <= 0 { 1 } else { size }
      let mut pos = 0
      while pos < input.length() {
        let end_ = if pos + chunk_size > input.length() {
          input.length()
        } else {
          pos + chunk_size
        }
        chunks.push(cst_substr(input, pos, end_))
        pos = end_
      }
    }
    None => {
      let lines = cmd_split_lines_preserve(input)
      let mut pos = 0
      while pos < lines.length() {
        let out = StringBuilder::new()
        let mut count = 0
        while pos < lines.length() && count < lines_per_chunk {
          out.write_string(lines[pos])
          pos += 1
          count += 1
        }
        chunks.push(out.to_string())
      }
    }
  }

  cmd_split_write_chunks(ctx, chunks, prefix)
}

// ============================================================================
// tar (minimal archive format for comparison tests)
// ============================================================================

fn tar_clean_path(path : String) -> String {
  if path == "/" {
    return path
  }
  let mut start = 0
  while start + 1 < path.length() &&
    path[start] == '.' &&
    path[start + 1] == '/' {
    start += 2
  }
  let trimmed = if start > 0 {
    path.substring(start=start)
  } else {
    path
  }
  let mut end_ = trimmed.length()
  while end_ > 1 && trimmed[end_ - 1] == '/' {
    end_ -= 1
  }
  if end_ == trimmed.length() {
    trimmed
  } else {
    trimmed.substring(start=0, end=end_)
  }
}

fn tar_collect_tree(
  fs : @fs.InMemoryFs,
  abs_path : String,
  rel_path : String,
  out : Array[TarEntry]
) -> Unit {
  let stat = try {
    fs.stat(abs_path)
  } catch {
    @fs.FsError(_msg) => return
  }

  if stat.is_directory {
    out.push({ path: rel_path + "/", is_dir: true, content: "" })
    let entries = try {
      fs.readdir(abs_path)
    } catch {
      @fs.FsError(_msg) => return
    }
    let names : Array[String] = []
    for entry in entries {
      names.push(entry.name)
    }
    cst_sort_strings(names)
    for name in names {
      let child_abs = if abs_path == "/" { "/" + name } else { abs_path + "/" + name }
      let child_rel = rel_path + "/" + name
      tar_collect_tree(fs, child_abs, child_rel, out)
    }
    return
  }

  if stat.is_file {
    let content = try {
      fs.read_file(abs_path)
    } catch {
      @fs.FsError(_msg) => ""
    }
    out.push({ path: rel_path, is_dir: false, content })
  }
}

fn tar_serialize(entries : Array[TarEntry]) -> String {
  let out = StringBuilder::new()
  out.write_string("MBTAR1\n")
  for entry in entries {
    if entry.is_dir {
      out.write_string("D\t")
      out.write_string(entry.path)
      out.write_char('\n')
    } else {
      out.write_string("F\t")
      out.write_string(entry.path)
      out.write_char('\t')
      out.write_string(entry.content.length().to_string())
      out.write_char('\n')
      out.write_string(entry.content)
      out.write_char('\n')
    }
  }
  out.to_string()
}

fn tar_index_of_char(s : String, start : Int, ch : Char) -> Int {
  for i = start; i < s.length(); i = i + 1 {
    if s[i].to_int().unsafe_to_char() == ch {
      return i
    }
  }
  -1
}

fn tar_deserialize(content : String) -> Array[TarEntry] {
  let entries : Array[TarEntry] = []
  if not(cst_starts_with(content, "MBTAR1\n")) {
    return entries
  }
  let mut pos = 7
  while pos < content.length() {
    let line_end = tar_index_of_char(content, pos, '\n')
    if line_end < 0 {
      break
    }
    let header = cst_substr(content, pos, line_end)
    pos = line_end + 1
    if header.length() == 0 {
      continue
    }

    if cst_starts_with(header, "D\t") {
      let path = header.substring(start=2)
      entries.push({ path, is_dir: true, content: "" })
      continue
    }

    if cst_starts_with(header, "F\t") {
      let tab2 = tar_index_of_char(header, 2, '\t')
      if tab2 < 0 {
        continue
      }
      let path = cst_substr(header, 2, tab2)
      let len_str = cst_substr(header, tab2 + 1, header.length())
      let mut size = cst_parse_int(len_str)
      if size < 0 {
        size = 0
      }
      let end_ = if pos + size > content.length() {
        content.length()
      } else {
        pos + size
      }
      let file_content = cst_substr(content, pos, end_)
      pos = end_
      if pos < content.length() && content[pos].to_int().unsafe_to_char() == '\n' {
        pos += 1
      }
      entries.push({ path, is_dir: false, content: file_content })
    }
  }
  entries
}

fn tar_strip_components(path : String, strip : Int) -> String? {
  let mut p = path
  let is_dir = p.length() > 0 && p[p.length() - 1] == '/'
  if is_dir && p.length() > 1 {
    p = p.substring(start=0, end=p.length() - 1)
  }
  let parts = cst_split_path(p)
  if strip >= parts.length() {
    return None
  }
  let stripped = cst_join_path(parts, strip)
  if stripped.length() == 0 {
    None
  } else if is_dir {
    Some(stripped + "/")
  } else {
    Some(stripped)
  }
}

fn cmd_tar(ctx : CommandContext) -> @ast.ExecResult {
  let mut mode = ""
  let mut archive_file : String? = None
  let mut extract_dir : String? = None
  let mut strip_components = 0
  let operands : Array[String] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]

    if arg == "-C" && i + 1 < ctx.args.length() {
      extract_dir = Some(ctx.args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("--strip-components=") {
      strip_components = cst_parse_int(arg.substring(start=19))
      if strip_components < 0 {
        strip_components = 0
      }
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      let mut j = 1
      while j < arg.length() {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'c' | 't' | 'x' => mode = flag.to_string()
          'z' => ()
          'f' => {
            if j + 1 < arg.length() {
              archive_file = Some(arg.substring(start=j + 1))
              j = arg.length()
            } else if i + 1 < ctx.args.length() {
              i += 1
              archive_file = Some(ctx.args[i])
            }
          }
          _ => ()
        }
        j += 1
      }
      i += 1
      continue
    }

    operands.push(arg)
    i += 1
  }

  let archive_path = match archive_file {
    Some(path) => path
    None => return @ast.ExecResult::err("tar: archive file not specified\n")
  }
  let archive_abs = try {
    @fs.resolve_path(ctx.cwd, archive_path)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
  }

  if mode == "c" {
    let entries : Array[TarEntry] = []
    for operand in operands {
      let rel = tar_clean_path(operand)
      let abs = try {
        @fs.resolve_path(ctx.cwd, rel)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
      }
      let stat = try {
        ctx.fs.stat(abs)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
      }
      if stat.is_directory {
        tar_collect_tree(ctx.fs, abs, rel, entries)
      } else {
        let content = try {
          ctx.fs.read_file(abs)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
        }
        entries.push({ path: rel, is_dir: false, content })
      }
    }
    let packed = tar_serialize(entries)
    try {
      ctx.fs.write_file(archive_abs, packed)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
    }
    return @ast.ExecResult::ok("")
  }

  let archive_content = try {
    ctx.fs.read_file(archive_abs)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
  }
  let entries = tar_deserialize(archive_content)

  if mode == "t" {
    let out = StringBuilder::new()
    for entry in entries {
      out.write_string(entry.path)
      out.write_char('\n')
    }
    return @ast.ExecResult::ok(out.to_string())
  }

  if mode == "x" {
    let dest_abs = match extract_dir {
      Some(dir) => {
        try {
          @fs.resolve_path(ctx.cwd, dir)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
        }
      }
      None => ctx.cwd
    }
    for entry in entries {
      let extracted = match tar_strip_components(entry.path, strip_components) {
        Some(path) => path
        None => continue
      }
      let clean = if extracted.length() > 0 && extracted[extracted.length() - 1] == '/' {
        extracted.substring(start=0, end=extracted.length() - 1)
      } else {
        extracted
      }
      let final_path = try {
        @fs.resolve_path(dest_abs, clean)
      } catch {
        @fs.FsError(_msg) => continue
      }

      if entry.is_dir {
        try {
          ctx.fs.mkdir(final_path, recursive=true)
        } catch {
          @fs.FsError(_msg) => ()
        }
      } else {
        try {
          ctx.fs.write_file(final_path, entry.content)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("tar: \{msg}\n")
        }
      }
    }
    return @ast.ExecResult::ok("")
  }

  @ast.ExecResult::err("tar: you must specify one of -c, -t, or -x\n")
}
