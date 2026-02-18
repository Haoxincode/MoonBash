// moon_bash Interpreter - Shell Utility Builtins
// whoami, hostname, help, clear, history, tac, od

fn ExecContext::builtin_whoami(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  self.stdout_buf.write_string(
    self.env.get("USER").unwrap_or("user") + "\n",
  )
  self.exit_code = 0
}

fn ExecContext::builtin_hostname(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  self.stdout_buf.write_string(
    self.env.get("HOSTNAME").unwrap_or("moon-bash") + "\n",
  )
  self.exit_code = 0
}

fn ExecContext::builtin_help(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  let text =
    #|MoonBash - POSIX Shell Sandbox
    #|
    #|File commands:    cat, ls, cp, mv, rm, mkdir, touch, chmod, ln, stat, file, tree, du
    #|Navigation:       cd, pwd, pushd, popd
    #|Text processing:  grep, sed, awk, sort, uniq, cut, head, tail, wc, tr, rev, nl, fold
    #|Text tools:       diff, comm, paste, join, column, expand, unexpand, tee, xargs
    #|Search:           find, grep, egrep, fgrep
    #|Data tools:       jq, base64, md5sum, sha256sum, od, tac
    #|Shell builtins:   echo, printf, read, test, eval, source, export, set, unset, declare
    #|Control flow:     if, for, while, until, case, function
    #|Environment:      env, printenv, which, type, basename, dirname, seq, date
    #|Other:            whoami, hostname, true, false, exit, history, help, clear
    #|
  self.stdout_buf.write_string(text)
  self.exit_code = 0
}

fn ExecContext::builtin_clear(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  // No-op in sandbox environment
  self.exit_code = 0
}

fn ExecContext::builtin_history(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  // No persistent history in sandbox
  self.exit_code = 0
}

fn ExecContext::builtin_tac(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let files : Array[String] = []
  for arg in args {
    files.push(arg)
  }

  if files.length() == 0 {
    // Read from stdin
    let lines = split_lines_no_trailing(self.stdin_buf)
    let mut i = lines.length() - 1
    while i >= 0 {
      self.stdout_buf.write_string(lines[i] + "\n")
      i -= 1
    }
    self.exit_code = 0
    return
  }

  for file in files {
    let resolved = try {
      @fs.resolve_path(self.cwd, file)
    } catch {
      _ => file
    }
    let content = try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("tac: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    let lines = split_lines_no_trailing(content)
    let mut i = lines.length() - 1
    while i >= 0 {
      self.stdout_buf.write_string(lines[i] + "\n")
      i -= 1
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_od(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut char_mode = false
  let mut hex_mode = false
  let mut hex_address = false
  let mut input_file : String? = None
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-c" {
      char_mode = true
      i += 1
    } else if arg == "-x" {
      hex_mode = true
      i += 1
    } else if arg == "-t" && i + 1 < args.length() {
      let fmt = args[i + 1]
      if fmt == "x2" {
        hex_mode = true
      }
      i += 2
    } else if arg == "-A" && i + 1 < args.length() {
      let fmt = args[i + 1]
      if fmt == "x" {
        hex_address = true
      }
      i += 2
    } else if arg.has_prefix("-A") && arg.length() > 2 {
      let fmt = arg.view(start_offset=2).to_string()
      if fmt == "x" {
        hex_address = true
      }
      i += 1
    } else if arg.has_prefix("-t") && arg.length() > 2 {
      let fmt = arg.view(start_offset=2).to_string()
      if fmt == "x2" {
        hex_mode = true
      }
      i += 1
    } else {
      input_file = Some(arg)
      i += 1
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("od: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let bytes : Array[Int] = []
  for j = 0; j < input.length(); j = j + 1 {
    bytes.push(input[j].to_int() & 0xFF)
  }

  let total = bytes.length()
  let mut offset = 0
  while offset < total {
    let line_end = if offset + 16 <= total { offset + 16 } else { total }
    // Print address
    if hex_address {
      self.stdout_buf.write_string(od_format_hex_addr(offset))
    } else {
      self.stdout_buf.write_string(od_format_octal_addr(offset))
    }

    if char_mode {
      // -c mode: named characters
      let mut j = offset
      while j < line_end {
        self.stdout_buf.write_string(od_format_char(bytes[j]))
        j += 1
      }
    } else if hex_mode {
      // -x mode: hex 2-byte words
      let mut j = offset
      while j < line_end {
        let lo = bytes[j]
        let hi = if j + 1 < line_end { bytes[j + 1] } else { 0 }
        let word = hi * 256 + lo
        self.stdout_buf.write_string(" ")
        self.stdout_buf.write_string(od_format_hex4(word))
        j += 2
      }
    } else {
      // Default: octal bytes
      let mut j = offset
      while j < line_end {
        let lo = bytes[j]
        let hi = if j + 1 < line_end { bytes[j + 1] } else { 0 }
        let word = hi * 256 + lo
        self.stdout_buf.write_string(" ")
        self.stdout_buf.write_string(od_format_octal6(word))
        j += 2
      }
    }
    self.stdout_buf.write_string("\n")
    offset = line_end
  }

  // Final offset line
  if hex_address {
    self.stdout_buf.write_string(od_format_hex_addr(total))
  } else {
    self.stdout_buf.write_string(od_format_octal_addr(total))
  }
  self.stdout_buf.write_string("\n")
  self.exit_code = 0
}

// Format a 7-digit octal address
fn od_format_octal_addr(n : Int) -> String {
  let buf = StringBuilder::new()
  let mut val = n
  let digits : Array[Char] = []
  if val == 0 {
    for j = 0; j < 7; j = j + 1 {
      ignore(j)
      digits.push('0')
    }
  } else {
    while val > 0 {
      digits.push((val % 8 + 48).unsafe_to_char())
      val = val / 8
    }
    while digits.length() < 7 {
      digits.push('0')
    }
  }
  // Reverse
  let mut i = digits.length() - 1
  while i >= 0 {
    buf.write_char(digits[i])
    i -= 1
  }
  buf.to_string()
}

// Format a hex address (6 digits)
fn od_format_hex_addr(n : Int) -> String {
  let buf = StringBuilder::new()
  let mut val = n
  let digits : Array[Char] = []
  let hex_chars = "0123456789abcdef"
  if val == 0 {
    for j = 0; j < 6; j = j + 1 {
      ignore(j)
      digits.push('0')
    }
  } else {
    while val > 0 {
      digits.push(hex_chars[val % 16].to_int().unsafe_to_char())
      val = val / 16
    }
    while digits.length() < 6 {
      digits.push('0')
    }
  }
  let mut i = digits.length() - 1
  while i >= 0 {
    buf.write_char(digits[i])
    i -= 1
  }
  buf.to_string()
}

// Format a single byte as a named character for -c mode
fn od_format_char(b : Int) -> String {
  match b {
    0 => "  \\0"
    7 => "  \\a"
    8 => "  \\b"
    9 => "  \\t"
    10 => "  \\n"
    12 => "  \\f"
    13 => "  \\r"
    _ =>
      if b >= 32 && b <= 126 {
        let buf = StringBuilder::new()
        buf.write_string("   ")
        buf.write_char(b.unsafe_to_char())
        buf.to_string()
      } else {
        // Octal escape for non-printable
        let d2 = b / 64
        let d1 = b % 64 / 8
        let d0 = b % 8
        let buf = StringBuilder::new()
        buf.write_char(' ')
        buf.write_char((d2 + 48).unsafe_to_char())
        buf.write_char((d1 + 48).unsafe_to_char())
        buf.write_char((d0 + 48).unsafe_to_char())
        buf.to_string()
      }
  }
}

// Format a 4-digit hex value
fn od_format_hex4(n : Int) -> String {
  let hex_chars = "0123456789abcdef"
  let buf = StringBuilder::new()
  buf.write_char(hex_chars[(n >> 12) & 0xF].to_int().unsafe_to_char())
  buf.write_char(hex_chars[(n >> 8) & 0xF].to_int().unsafe_to_char())
  buf.write_char(hex_chars[(n >> 4) & 0xF].to_int().unsafe_to_char())
  buf.write_char(hex_chars[n & 0xF].to_int().unsafe_to_char())
  buf.to_string()
}

// Format a 6-digit octal value
fn od_format_octal6(n : Int) -> String {
  let buf = StringBuilder::new()
  let mut val = n
  let digits : Array[Char] = []
  if val == 0 {
    for j = 0; j < 6; j = j + 1 {
      ignore(j)
      digits.push('0')
    }
  } else {
    while val > 0 {
      digits.push((val % 8 + 48).unsafe_to_char())
      val = val / 8
    }
    while digits.length() < 6 {
      digits.push('0')
    }
  }
  let mut i = digits.length() - 1
  while i >= 0 {
    buf.write_char(digits[i])
    i -= 1
  }
  buf.to_string()
}
