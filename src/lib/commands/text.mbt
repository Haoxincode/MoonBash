// MoonBash Commands - Text Processing
// head, tail, wc

/// Safely extract substring from start index to end of string.
fn cmd_substr_from(s : String, start : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < s.length(); i = i + 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

/// Safely extract substring from [start, end).
fn cmd_substr_slice(s : String, start : Int, end_ : Int) -> String {
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
  let buf = StringBuilder::new()
  for i = start; i < end_; i = i + 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

/// Helper to split string into lines
fn cmd_split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

/// Helper to parse an integer from a string
fn cmd_parse_int(s : String) -> Int {
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

/// head: output the first N lines (default 10)
fn cmd_head(ctx : CommandContext) -> @ast.ExecResult {
  let mut num_lines = 10
  let mut num_bytes : Int? = None
  let input_files : Array[String] = []
  let mut i = 0
  while i < ctx.args.length() {
    if ctx.args[i] == "-n" && i + 1 < ctx.args.length() {
      num_lines = cmd_parse_int(ctx.args[i + 1])
      i += 2
    } else if ctx.args[i].has_prefix("-n") && ctx.args[i].length() > 2 {
      // Handle -nN shorthand
      num_lines = cmd_parse_int(cmd_substr_from(ctx.args[i], 2))
      i += 1
    } else if ctx.args[i] == "-c" && i + 1 < ctx.args.length() {
      num_bytes = Some(cmd_parse_int(ctx.args[i + 1]))
      i += 2
    } else if ctx.args[i].has_prefix("-c") && ctx.args[i].length() > 2 {
      num_bytes = Some(cmd_parse_int(cmd_substr_from(ctx.args[i], 2)))
      i += 1
    } else if ctx.args[i].has_prefix("-") && ctx.args[i].length() > 1 {
      // Handle -N shorthand
      num_lines = cmd_parse_int(cmd_substr_from(ctx.args[i], 1))
      i += 1
    } else {
      input_files.push(ctx.args[i])
      i += 1
    }
  }

  let out = StringBuilder::new()

  if input_files.length() == 0 {
    match num_bytes {
      Some(byte_count) => {
        let count = if byte_count < 0 { 0 } else { byte_count }
        out.write_string(cmd_substr_slice(ctx.stdin_content, 0, count))
      }
      None => {
        let lines = cmd_split_lines(ctx.stdin_content)
        let count = if num_lines < lines.length() { num_lines } else { lines.length() }
        for j = 0; j < count; j = j + 1 {
          out.write_string(lines[j])
          out.write_char('\n')
        }
      }
    }
    return @ast.ExecResult::ok(out.to_string())
  }

  for file_idx = 0; file_idx < input_files.length(); file_idx = file_idx + 1 {
    let path = input_files[file_idx]
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("head: \{msg}\n")
    }
    let input = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("head: \{msg}\n")
    }

    if input_files.length() > 1 {
      if file_idx > 0 {
        out.write_char('\n')
      }
      out.write_string("==> \{path} <==\n")
    }

    match num_bytes {
      Some(byte_count) => {
        let count = if byte_count < 0 { 0 } else { byte_count }
        out.write_string(cmd_substr_slice(input, 0, count))
      }
      None => {
        let lines = cmd_split_lines(input)
        let count = if num_lines < lines.length() { num_lines } else { lines.length() }
        for j = 0; j < count; j = j + 1 {
          out.write_string(lines[j])
          out.write_char('\n')
        }
      }
    }
  }

  @ast.ExecResult::ok(out.to_string())
}

/// tail: output the last N lines (default 10)
fn cmd_tail(ctx : CommandContext) -> @ast.ExecResult {
  let mut num_lines = 10
  let mut num_bytes : Int? = None
  let input_files : Array[String] = []
  let mut i = 0
  while i < ctx.args.length() {
    if ctx.args[i] == "-n" && i + 1 < ctx.args.length() {
      let arg = ctx.args[i + 1]
      if arg.has_prefix("+") {
        // tail -n +N means starting from line N
        num_lines = -(cmd_parse_int(cmd_substr_from(arg, 1)))
      } else {
        num_lines = cmd_parse_int(arg)
      }
      i += 2
    } else if ctx.args[i].has_prefix("-n") && ctx.args[i].length() > 2 {
      let arg = cmd_substr_from(ctx.args[i], 2)
      if arg.has_prefix("+") {
        num_lines = -(cmd_parse_int(cmd_substr_from(arg, 1)))
      } else {
        num_lines = cmd_parse_int(arg)
      }
      i += 1
    } else if ctx.args[i] == "-c" && i + 1 < ctx.args.length() {
      num_bytes = Some(cmd_parse_int(ctx.args[i + 1]))
      i += 2
    } else if ctx.args[i].has_prefix("-c") && ctx.args[i].length() > 2 {
      num_bytes = Some(cmd_parse_int(cmd_substr_from(ctx.args[i], 2)))
      i += 1
    } else if ctx.args[i].has_prefix("-") && ctx.args[i].length() > 1 {
      num_lines = cmd_parse_int(cmd_substr_from(ctx.args[i], 1))
      i += 1
    } else {
      input_files.push(ctx.args[i])
      i += 1
    }
  }

  let out = StringBuilder::new()

  if input_files.length() == 0 {
    match num_bytes {
      Some(byte_count) => {
        let count = if byte_count < 0 { 0 } else { byte_count }
        let start = if count >= ctx.stdin_content.length() {
          0
        } else {
          ctx.stdin_content.length() - count
        }
        out.write_string(cmd_substr_slice(ctx.stdin_content, start, ctx.stdin_content.length()))
      }
      None => {
        let lines = cmd_split_lines(ctx.stdin_content)
        if num_lines < 0 {
          // tail -n +N (starting from line N, 1-indexed)
          let start = -num_lines - 1
          for j = start; j < lines.length(); j = j + 1 {
            out.write_string(lines[j])
            out.write_char('\n')
          }
        } else {
          let start = if num_lines >= lines.length() {
            0
          } else {
            lines.length() - num_lines
          }
          for j = start; j < lines.length(); j = j + 1 {
            out.write_string(lines[j])
            out.write_char('\n')
          }
        }
      }
    }
    return @ast.ExecResult::ok(out.to_string())
  }

  for file_idx = 0; file_idx < input_files.length(); file_idx = file_idx + 1 {
    let path = input_files[file_idx]
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("tail: \{msg}\n")
    }
    let input = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("tail: \{msg}\n")
    }

    if input_files.length() > 1 {
      if file_idx > 0 {
        out.write_char('\n')
      }
      out.write_string("==> \{path} <==\n")
    }

    match num_bytes {
      Some(byte_count) => {
        let count = if byte_count < 0 { 0 } else { byte_count }
        let start = if count >= input.length() {
          0
        } else {
          input.length() - count
        }
        out.write_string(cmd_substr_slice(input, start, input.length()))
      }
      None => {
        let lines = cmd_split_lines(input)
        if num_lines < 0 {
          // tail -n +N (starting from line N, 1-indexed)
          let start = -num_lines - 1
          for j = start; j < lines.length(); j = j + 1 {
            out.write_string(lines[j])
            out.write_char('\n')
          }
        } else {
          let start = if num_lines >= lines.length() {
            0
          } else {
            lines.length() - num_lines
          }
          for j = start; j < lines.length(); j = j + 1 {
            out.write_string(lines[j])
            out.write_char('\n')
          }
        }
      }
    }
  }

  @ast.ExecResult::ok(out.to_string())
}

/// wc: word, line, character count
fn cmd_wc_count(input : String) -> (Int, Int, Int) {
  // Count lines
  let mut line_count = 0
  for i = 0; i < input.length(); i = i + 1 {
    if input[i] == '\n' {
      line_count += 1
    }
  }

  // Count words
  let mut word_count = 0
  let mut in_word = false
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      in_word = false
    } else if not(in_word) {
      word_count += 1
      in_word = true
    }
  }

  // Count chars
  let char_count = input.length()
  (line_count, word_count, char_count)
}

fn cmd_wc_write_row(
  out : StringBuilder,
  line_count : Int,
  word_count : Int,
  char_count : Int,
  show_lines : Bool,
  show_words : Bool,
  show_chars : Bool,
  label : String?
) -> Unit {
  let mut first = true
  if show_lines {
    if not(first) { out.write_char(' ') }
    out.write_string(line_count.to_string())
    first = false
  }
  if show_words {
    if not(first) { out.write_char(' ') }
    out.write_string(word_count.to_string())
    first = false
  }
  if show_chars {
    if not(first) { out.write_char(' ') }
    out.write_string(char_count.to_string())
    first = false
  }
  match label {
    Some(name) => out.write_string(" " + name)
    None => ()
  }
  out.write_char('\n')
}

fn cmd_wc(ctx : CommandContext) -> @ast.ExecResult {
  let mut flag_lines = false
  let mut flag_words = false
  let mut flag_chars = false
  let input_files : Array[String] = []

  for arg in ctx.args {
    match arg {
      "-l" => flag_lines = true
      "-w" => flag_words = true
      "-c" | "-m" => flag_chars = true
      "-lw" | "-wl" => { flag_lines = true; flag_words = true }
      "-lc" | "-cl" => { flag_lines = true; flag_chars = true }
      "-wc" | "-cw" => { flag_words = true; flag_chars = true }
      "-lwc" | "-lcw" | "-wlc" | "-wcl" | "-clw" | "-cwl" => {
        flag_lines = true
        flag_words = true
        flag_chars = true
      }
      _ => input_files.push(arg)
    }
  }

  // Default: show all
  if not(flag_lines) && not(flag_words) && not(flag_chars) {
    flag_lines = true
    flag_words = true
    flag_chars = true
  }

  let out = StringBuilder::new()

  if input_files.length() == 0 {
    let (line_count, word_count, char_count) = cmd_wc_count(ctx.stdin_content)
    cmd_wc_write_row(
      out,
      line_count,
      word_count,
      char_count,
      flag_lines,
      flag_words,
      flag_chars,
      None,
    )
    return @ast.ExecResult::ok(out.to_string())
  }

  let mut total_lines = 0
  let mut total_words = 0
  let mut total_chars = 0

  for path in input_files {
    let input = {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, path)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("wc: \{msg}\n")
      }
      try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("wc: \{msg}\n")
      }
    }

    let (line_count, word_count, char_count) = cmd_wc_count(input)
    total_lines += line_count
    total_words += word_count
    total_chars += char_count

    cmd_wc_write_row(
      out,
      line_count,
      word_count,
      char_count,
      flag_lines,
      flag_words,
      flag_chars,
      Some(path),
    )
  }

  if input_files.length() > 1 {
    cmd_wc_write_row(
      out,
      total_lines,
      total_words,
      total_chars,
      flag_lines,
      flag_words,
      flag_chars,
      Some("total"),
    )
  }

  @ast.ExecResult::ok(out.to_string())
}
