// MoonBash Interpreter - Common Helpers
// Shared utilities used across interpreter modules.

fn is_shell_builtin(name : String) -> Bool {
  match name {
    "export" | "unset" | "set" | "shift" | "exit" | "return" | "break"
    | "continue" | "read" | "test" | "[" | "[[" | "printf" | "eval" | "source"
    | "." | "local" | "declare" | "typeset" | ":" | "type" | "command" | "basename"
    | "dirname" | "seq" | "rev" | "nl" | "fold" | "expand" | "unexpand" | "paste"
    | "column" | "join" | "tr" | "sort" | "uniq" | "cut" | "tee" | "sed" | "grep"
    | "egrep" | "fgrep" | "rg" | "xargs" | "date" | "env" | "printenv"
    | "which" => true
    _ => false
  }
}

fn parse_int_str(s : String) -> Int {
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

fn split_by_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' {
      let word = buf.to_string()
      if word.length() > 0 {
        result.push(word)
        buf.reset()
      }
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

fn split_lines(s : String) -> Array[String] {
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

fn split_lines_no_trailing(s : String) -> Array[String] {
  if s.length() == 0 {
    return []
  }
  let lines = split_lines(s)
  // Remove trailing empty line if the input ended with \n
  if lines.length() > 0 && lines[lines.length() - 1] == "" {
    let result : Array[String] = []
    for i = 0; i < lines.length() - 1; i = i + 1 {
      result.push(lines[i])
    }
    result
  } else {
    lines
  }
}

fn repeat_char(ch : Char, count : Int) -> String {
  let out = StringBuilder::new()
  let total = if count < 0 { 0 } else { count }
  for i = 0; i < total; i = i + 1 {
    out.write_char(ch)
  }
  out.to_string()
}

fn contains_substring(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  for i = 0; i <= haystack.length() - needle.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < needle.length(); j = j + 1 {
      if haystack[i + j] != needle[j] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }
  false
}


fn substring_slice(s : String, start : Int, end : Int) -> String {
  if start >= end || start < 0 || end > s.length() {
    return ""
  }
  s.substring(start=start, end=end)
}


fn parse_field_spec(spec : String) -> Array[Int] {
  let fields : Array[Int] = []
  let parts = split_string_by_delimiter(spec, ",")
  for part in parts {
    // Handle ranges like 1-3
    if contains_substring(part, "-") {
      let range_parts = split_string_by_delimiter(part, "-")
      if range_parts.length() == 2 {
        let start = parse_int_str(range_parts[0])
        let end = parse_int_str(range_parts[1])
        for i = start; i <= end; i = i + 1 {
          fields.push(i)
        }
      }
    } else {
      fields.push(parse_int_str(part))
    }
  }
  fields
}

fn split_string_by_delimiter(s : String, delim : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let delim_len = delim.length()
  if delim_len == 0 {
    result.push(s)
    return result
  }
  let mut i = 0
  while i < s.length() {
    let mut match_found = true
    if i + delim_len <= s.length() {
      for j = 0; j < delim_len; j = j + 1 {
        if s[i + j] != delim[j] {
          match_found = false
          break
        }
      }
    } else {
      match_found = false
    }
    if match_found {
      result.push(buf.to_string())
      buf.reset()
      i += delim_len
    } else {
      buf.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  result.push(buf.to_string())
  result
}

// ============================================================================
// Test Evaluation
// ============================================================================

fn evaluate_test(args : Array[String], ctx : ExecContext) -> Bool {
  // Logical operators inside test/[ ... ].
  // Implement minimal precedence: -a binds tighter than -o.
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "-o" {
      let left : Array[String] = []
      let right : Array[String] = []
      for j = 0; j < i; j = j + 1 {
        left.push(args[j])
      }
      for j = i + 1; j < args.length(); j = j + 1 {
        right.push(args[j])
      }
      return evaluate_test(left, ctx) || evaluate_test(right, ctx)
    }
  }
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "-a" {
      let left : Array[String] = []
      let right : Array[String] = []
      for j = 0; j < i; j = j + 1 {
        left.push(args[j])
      }
      for j = i + 1; j < args.length(); j = j + 1 {
        right.push(args[j])
      }
      return evaluate_test(left, ctx) && evaluate_test(right, ctx)
    }
  }

  if args.length() == 0 {
    return false
  }
  if args.length() == 1 {
    // test STRING: true if string is non-empty
    return args[0].length() > 0
  }
  if args.length() == 2 {
    let op = args[0]
    let arg = args[1]
    match op {
      "-z" => return arg.length() == 0
      "-n" => return arg.length() > 0
      "-f" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(_)) => true
          _ => false
        }
      }
      "-d" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Directory(_)) => true
          _ => false
        }
      }
      "-e" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-s" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(data)) => data.content.length() > 0
          _ => false
        }
      }
      "-r" | "-w" | "-x" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-L" | "-h" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Symlink(_)) => true
          _ => false
        }
      }
      "!" => return not(evaluate_test([arg], ctx))
      _ => ()
    }
  }
  if args.length() == 3 {
    let left = args[0]
    let op = args[1]
    let right = args[2]
    match op {
      "=" | "==" => return left == right
      "!=" => return left != right
      "-eq" => return parse_int_str(left) == parse_int_str(right)
      "-ne" => return parse_int_str(left) != parse_int_str(right)
      "-lt" => return parse_int_str(left) < parse_int_str(right)
      "-le" => return parse_int_str(left) <= parse_int_str(right)
      "-gt" => return parse_int_str(left) > parse_int_str(right)
      "-ge" => return parse_int_str(left) >= parse_int_str(right)
      "-nt" | "-ot" | "-ef" => return false // File comparison not meaningful in sandbox
      _ => ()
    }
  }
  if args.length() == 4 && args[0] == "!" {
    return not(evaluate_test([args[1], args[2], args[3]], ctx))
  }
  false
}

// ============================================================================
// Printf Implementation
// ============================================================================

fn format_printf(format : String, args : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  let mut arg_idx = 0

  while i < format.length() {
    let ch = format[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < format.length() {
      let next = format[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => { buf.write_char('\n'); i += 2 }
        't' => { buf.write_char('\t'); i += 2 }
        '\\' => { buf.write_char('\\'); i += 2 }
        '"' => { buf.write_char('"'); i += 2 }
        '0' => { buf.write_char('\u0000'); i += 2 }
        _ => { buf.write_char('\\'); buf.write_char(next); i += 2 }
      }
    } else if ch == '%' && i + 1 < format.length() {
      let spec = format[i + 1].to_int().unsafe_to_char()
      match spec {
        's' => {
          if arg_idx < args.length() {
            buf.write_string(args[arg_idx])
            arg_idx += 1
          }
          i += 2
        }
        'd' => {
          if arg_idx < args.length() {
            buf.write_string(parse_int_str(args[arg_idx]).to_string())
            arg_idx += 1
          }
          i += 2
        }
        '%' => {
          buf.write_char('%')
          i += 2
        }
        _ => {
          buf.write_char('%')
          i += 1
        }
      }
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}
