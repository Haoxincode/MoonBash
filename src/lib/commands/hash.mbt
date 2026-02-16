// moon_bash Commands - Hash commands (md5sum, sha1sum, sha256sum)
// Uses community packages: gmlewis/md5, gmlewis/sha1, shu-kitamura/sha256

/// Convert a string to an array of bytes (treating each char as a byte).
fn string_to_bytes(s : String) -> Bytes {
  let arr : Array[Byte] = Array::new()
  for i = 0; i < s.length(); i = i + 1 {
    arr.push((s[i].to_int() & 0xFF).to_byte())
  }
  Bytes::from_array(arr)
}

/// md5sum: compute MD5 message digest
fn cmd_md5sum(ctx : CommandContext) -> @ast.ExecResult {
  let mut check_mode = false
  let files : Array[String] = []
  for arg in ctx.args {
    if arg == "-c" || arg == "--check" {
      check_mode = true
    } else {
      files.push(arg)
    }
  }

  if check_mode {
    return hash_check(ctx, files, "md5sum", compute_md5)
  }

  if files.length() == 0 {
    // Read from stdin
    let hash = compute_md5(ctx.stdin_content)
    return @ast.ExecResult::ok(hash + "  -\n")
  }

  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut had_error = false
  for file in files {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, file)
    } catch {
      _ => file
    }
    let content = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("md5sum: \{msg}\n")
        had_error = true
        continue
      }
    }
    let hash = compute_md5(content)
    buf.write_string(hash + "  " + file + "\n")
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=if had_error { 1 } else { 0 },
  )
}

/// sha1sum: compute SHA1 message digest
fn cmd_sha1sum(ctx : CommandContext) -> @ast.ExecResult {
  let mut check_mode = false
  let files : Array[String] = []
  for arg in ctx.args {
    if arg == "-c" || arg == "--check" {
      check_mode = true
    } else {
      files.push(arg)
    }
  }

  if check_mode {
    return hash_check(ctx, files, "sha1sum", compute_sha1)
  }

  if files.length() == 0 {
    let hash = compute_sha1(ctx.stdin_content)
    return @ast.ExecResult::ok(hash + "  -\n")
  }

  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut had_error = false
  for file in files {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, file)
    } catch {
      _ => file
    }
    let content = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("sha1sum: \{msg}\n")
        had_error = true
        continue
      }
    }
    let hash = compute_sha1(content)
    buf.write_string(hash + "  " + file + "\n")
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=if had_error { 1 } else { 0 },
  )
}

/// sha256sum: compute SHA256 message digest
fn cmd_sha256sum(ctx : CommandContext) -> @ast.ExecResult {
  let mut check_mode = false
  let files : Array[String] = []
  for arg in ctx.args {
    if arg == "-c" || arg == "--check" {
      check_mode = true
    } else {
      files.push(arg)
    }
  }

  if check_mode {
    return hash_check(ctx, files, "sha256sum", compute_sha256)
  }

  if files.length() == 0 {
    let hash = compute_sha256(ctx.stdin_content)
    return @ast.ExecResult::ok(hash + "  -\n")
  }

  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut had_error = false
  for file in files {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, file)
    } catch {
      _ => file
    }
    let content = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        errbuf.write_string("sha256sum: \{msg}\n")
        had_error = true
        continue
      }
    }
    let hash = compute_sha256(content)
    buf.write_string(hash + "  " + file + "\n")
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=if had_error { 1 } else { 0 },
  )
}

/// Compute MD5 hash of a string, returns hex digest.
fn compute_md5(input : String) -> String {
  let digest = @md5.Digest::new()
  for i = 0; i < input.length(); i = i + 1 {
    digest.write((input[i].to_int() & 0xFF).to_byte())
  }
  digest.check_sum()
}

/// Compute SHA1 hash of a string, returns hex digest.
fn compute_sha1(input : String) -> String {
  let digest = @sha1.Digest::new()
  for i = 0; i < input.length(); i = i + 1 {
    let _ = digest.write_byte((input[i].to_int() & 0xFF).to_byte())

  }
  digest.check_sum()
}

/// Compute SHA256 hash of a string, returns hex digest.
fn compute_sha256(input : String) -> String {
  let bytes = string_to_bytes(input)
  @sha256.sha256_hexdigest(bytes)
}

/// Shared -c (check) logic for all hash commands.
fn hash_check(
  ctx : CommandContext,
  files : Array[String],
  cmd_name : String,
  hash_fn : (String) -> String
) -> @ast.ExecResult {
  // Read hash file (first file arg, or stdin)
  let check_content = if files.length() > 0 {
    let path = files[0]
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      _ => path
    }
    try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) =>
        return @ast.ExecResult::err("\{cmd_name}: \{msg}\n")
    }
  } else {
    ctx.stdin_content
  }

  let buf = StringBuilder::new()
  let errbuf = StringBuilder::new()
  let mut failures = 0
  let lines = hash_split_lines(check_content)
  for line in lines {
    if line.length() == 0 {
      continue
    }
    // Parse "hash  filename" format
    let parsed = hash_parse_check_line(line)
    match parsed {
      None => {
        errbuf.write_string(
          "\{cmd_name}: \{line}: improperly formatted checksum line\n",
        )
        continue
      }
      Some((expected_hash, filename)) => {
        let resolved = try {
          @fs.resolve_path(ctx.cwd, filename)
        } catch {
          _ => filename
        }
        let content = try {
          ctx.fs.read_file(resolved)
        } catch {
          @fs.FsError(_) => {
            errbuf.write_string(
              "\{cmd_name}: \{filename}: No such file or directory\n",
            )
            buf.write_string("\{filename}: FAILED open or read\n")
            failures += 1
            continue
          }
        }
        let actual_hash = hash_fn(content)
        if actual_hash == expected_hash {
          buf.write_string("\{filename}: OK\n")
        } else {
          buf.write_string("\{filename}: FAILED\n")
          failures += 1
        }
      }
    }
  }
  if failures > 0 {
    errbuf.write_string(
      "\{cmd_name}: WARNING: \{failures} computed checksum did NOT match\n",
    )
  }
  @ast.ExecResult::new(
    stdout=buf.to_string(),
    stderr=errbuf.to_string(),
    exit_code=if failures > 0 { 1 } else { 0 },
  )
}

/// Split a string into lines, excluding trailing empty line.
fn hash_split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(s[i].to_int().unsafe_to_char())
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    lines.push(remaining)
  }
  lines
}

/// Parse a check line "hash  filename" or "hash filename".
/// Returns (hash, filename) or None if malformed.
fn hash_parse_check_line(line : String) -> (String, String)? {
  // Find first whitespace after hash
  let mut i = 0
  while i < line.length() && line[i] != ' ' && line[i] != '\t' {
    i += 1
  }
  if i == 0 || i >= line.length() {
    return None
  }
  let hash = line.substring(start=0, end=i)
  // Skip whitespace (typically two spaces or space+asterisk)
  while i < line.length() && (line[i] == ' ' || line[i] == '\t' || line[i] == '*') {
    i += 1
  }
  if i >= line.length() {
    return None
  }
  let filename = line.substring(start=i)
  Some((hash, filename))
}
