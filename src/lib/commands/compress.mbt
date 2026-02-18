// moon_bash Commands - Compression
// gzip, gunzip, zcat
//
// Simplified sandbox implementation: "compressed" content is the original
// content prefixed with a 2-byte magic header (\x1F\x8B). This lets
// gzip/gunzip/zcat round-trip correctly inside the VFS without requiring
// a real DEFLATE library.

/// The two-char magic header that marks our sandbox gzip format.
let gzip_magic_0 : Int = 0x1F

let gzip_magic_1 : Int = 0x8B

/// Check whether content starts with the gzip magic header.
fn is_gzip_content(content : String) -> Bool {
  content.length() >= 2 &&
    content[0].to_int() == gzip_magic_0 &&
    content[1].to_int() == gzip_magic_1
}

/// "Compress": prepend magic header to content.
fn gzip_encode(content : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char(gzip_magic_0.unsafe_to_char())
  buf.write_char(gzip_magic_1.unsafe_to_char())
  buf.write_string(content)
  buf.to_string()
}

/// "Decompress": strip the 2-byte magic header.
fn gzip_decode(content : String) -> String {
  if content.length() <= 2 {
    return ""
  }
  content.view(start_offset=2).to_string()
}

/// Check whether a filename ends with a given suffix.
fn str_ends_with(s : String, suffix : String) -> Bool {
  if suffix.length() > s.length() {
    return false
  }
  let offset = s.length() - suffix.length()
  for i = 0; i < suffix.length(); i = i + 1 {
    if s[offset + i] != suffix[i] {
      return false
    }
  }
  true
}

/// Strip a suffix from a string if present, otherwise return the string.
fn str_strip_suffix(s : String, suffix : String) -> String {
  if str_ends_with(s, suffix) {
    s.view(start_offset=0, end_offset=s.length() - suffix.length()).to_string()
  } else {
    s
  }
}

/// Core gunzip logic shared by cmd_gunzip and cmd_gzip -d.
fn gunzip_core(
  ctx : CommandContext,
  keep : Bool,
  to_stdout : Bool,
  force : Bool
) -> @ast.ExecResult {
  if ctx.args.length() == 0 && ctx.stdin_content.length() == 0 {
    return @ast.ExecResult::err("gunzip: missing operand\n")
  }
  // If no file args, decompress stdin to stdout
  if ctx.args.length() == 0 {
    if not(is_gzip_content(ctx.stdin_content)) {
      return @ast.ExecResult::err("gunzip: stdin: not in gzip format\n")
    }
    return @ast.ExecResult::ok(gzip_decode(ctx.stdin_content))
  }
  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for arg in ctx.args {
    if not(str_ends_with(arg, ".gz")) && not(str_ends_with(arg, ".tgz")) &&
      not(force) {
      errbuf.write_string("gunzip: \{arg}: unknown suffix -- ignored\n")
      exit_code = 1
      continue
    }
    let resolved = try {
      @fs.resolve_path(ctx.cwd, arg)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("gunzip: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    let content = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(_msg) => {
        errbuf.write_string("gunzip: \{arg}: No such file or directory\n")
        exit_code = 1
        continue
      }
    }
    if not(is_gzip_content(content)) {
      errbuf.write_string("gunzip: \{arg}: not in gzip format\n")
      exit_code = 1
      continue
    }
    let decoded = gzip_decode(content)
    if to_stdout {
      out.write_string(decoded)
    } else {
      let out_name = if str_ends_with(arg, ".tgz") {
        str_strip_suffix(arg, ".tgz") + ".tar"
      } else {
        str_strip_suffix(arg, ".gz")
      }
      let out_resolved = try {
        @fs.resolve_path(ctx.cwd, out_name)
      } catch {
        @fs.FsError(msg) => {
          errbuf.write_string("gunzip: \{msg}\n")
          exit_code = 1
          continue
        }
      }
      if not(force) && ctx.fs.exists(out_resolved) {
        errbuf.write_string(
          "gunzip: \{out_name}: already exists; not overwritten\n",
        )
        exit_code = 1
        continue
      }
      try {
        ctx.fs.write_file(out_resolved, decoded)
      } catch {
        @fs.FsError(msg) => {
          errbuf.write_string("gunzip: \{msg}\n")
          exit_code = 1
          continue
        }
      }
      if not(keep) {
        try {
          ctx.fs.rm(resolved)
        } catch {
          @fs.FsError(msg) => {
            errbuf.write_string("gunzip: \{msg}\n")
            exit_code = 1
          }
        }
      }
    }
  }
  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

/// gzip: compress files
fn cmd_gzip(ctx : CommandContext) -> @ast.ExecResult {
  let mut keep = false
  let mut decompress = false
  let mut to_stdout = false
  let mut force = false
  let files : Array[String] = []
  for arg in ctx.args {
    match arg {
      "-k" => keep = true
      "-d" => decompress = true
      "-c" => to_stdout = true
      "-f" => force = true
      "-kc" | "-ck" => { keep = true; to_stdout = true }
      "-kf" | "-fk" => { keep = true; force = true }
      "-cf" | "-fc" => { to_stdout = true; force = true }
      "-dc" | "-cd" => { decompress = true; to_stdout = true }
      "-df" | "-fd" => { decompress = true; force = true }
      "-dk" | "-kd" => { decompress = true; keep = true }
      _ => files.push(arg)
    }
  }
  // Build a context with just the file args for delegation
  let file_ctx : CommandContext = {
    args: files,
    stdin_content: ctx.stdin_content,
    cwd: ctx.cwd,
    env: ctx.env,
    fs: ctx.fs,
  }
  if decompress {
    return gunzip_core(file_ctx, keep, to_stdout, force)
  }
  if files.length() == 0 && ctx.stdin_content.length() == 0 {
    return @ast.ExecResult::err("gzip: missing operand\n")
  }
  // If no file args, compress stdin to stdout
  if files.length() == 0 {
    return @ast.ExecResult::ok(gzip_encode(ctx.stdin_content))
  }
  let out = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut exit_code = 0
  for file in files {
    if str_ends_with(file, ".gz") {
      errbuf.write_string("gzip: \{file}: already has .gz suffix -- unchanged\n")
      exit_code = 1
      continue
    }
    let resolved = try {
      @fs.resolve_path(ctx.cwd, file)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("gzip: \{msg}\n")
        exit_code = 1
        continue
      }
    }
    let content = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(_msg) => {
        errbuf.write_string("gzip: \{file}: No such file or directory\n")
        exit_code = 1
        continue
      }
    }
    let encoded = gzip_encode(content)
    if to_stdout {
      out.write_string(encoded)
    } else {
      let gz_name = file + ".gz"
      let gz_resolved = try {
        @fs.resolve_path(ctx.cwd, gz_name)
      } catch {
        @fs.FsError(msg) => {
          errbuf.write_string("gzip: \{msg}\n")
          exit_code = 1
          continue
        }
      }
      if not(force) && ctx.fs.exists(gz_resolved) {
        errbuf.write_string(
          "gzip: \{gz_name}: already exists; not overwritten\n",
        )
        exit_code = 1
        continue
      }
      try {
        ctx.fs.write_file(gz_resolved, encoded)
      } catch {
        @fs.FsError(msg) => {
          errbuf.write_string("gzip: \{msg}\n")
          exit_code = 1
          continue
        }
      }
      if not(keep) {
        try {
          ctx.fs.rm(resolved)
        } catch {
          @fs.FsError(msg) => {
            errbuf.write_string("gzip: \{msg}\n")
            exit_code = 1
          }
        }
      }
    }
  }
  @ast.ExecResult::new(
    stdout=out.to_string(),
    stderr=errbuf.to_string(),
    exit_code=exit_code,
  )
}

/// gunzip: decompress files
fn cmd_gunzip(ctx : CommandContext) -> @ast.ExecResult {
  let mut keep = false
  let mut to_stdout = false
  let mut force = false
  let files : Array[String] = []
  for arg in ctx.args {
    match arg {
      "-k" => keep = true
      "-c" => to_stdout = true
      "-f" => force = true
      "-kc" | "-ck" => { keep = true; to_stdout = true }
      "-kf" | "-fk" => { keep = true; force = true }
      "-cf" | "-fc" => { to_stdout = true; force = true }
      _ => files.push(arg)
    }
  }
  let file_ctx : CommandContext = {
    args: files,
    stdin_content: ctx.stdin_content,
    cwd: ctx.cwd,
    env: ctx.env,
    fs: ctx.fs,
  }
  gunzip_core(file_ctx, keep, to_stdout, force)
}

/// zcat: decompress to stdout (equivalent to gunzip -c)
fn cmd_zcat(ctx : CommandContext) -> @ast.ExecResult {
  let files : Array[String] = []
  let mut force = false
  for arg in ctx.args {
    match arg {
      "-f" => force = true
      _ => files.push(arg)
    }
  }
  let file_ctx : CommandContext = {
    args: files,
    stdin_content: ctx.stdin_content,
    cwd: ctx.cwd,
    env: ctx.env,
    fs: ctx.fs,
  }
  gunzip_core(file_ctx, true, true, force)
}
