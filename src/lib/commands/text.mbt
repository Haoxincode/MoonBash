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
  let mut input_file : String? = None
  let mut i = 0
  while i < ctx.args.length() {
    if ctx.args[i] == "-n" && i + 1 < ctx.args.length() {
      num_lines = cmd_parse_int(ctx.args[i + 1])
      i += 2
    } else if ctx.args[i].has_prefix("-") && ctx.args[i].length() > 1 {
      // Handle -N shorthand
      num_lines = cmd_parse_int(cmd_substr_from(ctx.args[i], 1))
      i += 1
    } else {
      input_file = Some(ctx.args[i])
      i += 1
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, path)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("head: \{msg}\n")
      }
      try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("head: \{msg}\n")
      }
    }
    None => ctx.stdin_content
  }

  let lines = cmd_split_lines(input)
  let buf = StringBuilder::new()
  let count = if num_lines < lines.length() { num_lines } else { lines.length() }
  for j = 0; j < count; j = j + 1 {
    buf.write_string(lines[j])
    buf.write_char('\n')
  }
  @ast.ExecResult::ok(buf.to_string())
}

/// tail: output the last N lines (default 10)
fn cmd_tail(ctx : CommandContext) -> @ast.ExecResult {
  let mut num_lines = 10
  let mut input_file : String? = None
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
    } else if ctx.args[i].has_prefix("-") && ctx.args[i].length() > 1 {
      num_lines = cmd_parse_int(cmd_substr_from(ctx.args[i], 1))
      i += 1
    } else {
      input_file = Some(ctx.args[i])
      i += 1
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, path)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("tail: \{msg}\n")
      }
      try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("tail: \{msg}\n")
      }
    }
    None => ctx.stdin_content
  }

  let lines = cmd_split_lines(input)
  let buf = StringBuilder::new()

  if num_lines < 0 {
    // tail -n +N (starting from line N, 1-indexed)
    let start = -num_lines - 1
    for j = start; j < lines.length(); j = j + 1 {
      buf.write_string(lines[j])
      buf.write_char('\n')
    }
  } else {
    let start = if num_lines >= lines.length() {
      0
    } else {
      lines.length() - num_lines
    }
    for j = start; j < lines.length(); j = j + 1 {
      buf.write_string(lines[j])
      buf.write_char('\n')
    }
  }
  @ast.ExecResult::ok(buf.to_string())
}

/// wc: word, line, character count
fn cmd_wc(ctx : CommandContext) -> @ast.ExecResult {
  let mut flag_lines = false
  let mut flag_words = false
  let mut flag_chars = false
  let mut input_file : String? = None

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
      _ => input_file = Some(arg)
    }
  }

  // Default: show all
  if not(flag_lines) && not(flag_words) && not(flag_chars) {
    flag_lines = true
    flag_words = true
    flag_chars = true
  }

  let input = match input_file {
    Some(path) => {
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
    None => ctx.stdin_content
  }

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
    } else {
      if not(in_word) {
        word_count += 1
        in_word = true
      }
    }
  }

  // Count chars
  let char_count = input.length()

  let buf = StringBuilder::new()
  let mut first = true
  if flag_lines {
    if not(first) { buf.write_char(' ') }
    buf.write_string(line_count.to_string())
    first = false
  }
  if flag_words {
    if not(first) { buf.write_char(' ') }
    buf.write_string(word_count.to_string())
    first = false
  }
  if flag_chars {
    if not(first) { buf.write_char(' ') }
    buf.write_string(char_count.to_string())
    first = false
  }
  match input_file {
    Some(path) => buf.write_string(" " + path)
    None => ()
  }
  buf.write_char('\n')
  @ast.ExecResult::ok(buf.to_string())
}
