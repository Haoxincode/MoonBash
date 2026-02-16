// moon_bash Commands - Text/Data Processing Extensions
// diff, cmp, comm, base64, expr

// ============================================================================
// diff - Compare files line by line
// ============================================================================

/// Read file content, supporting "-" for stdin. Returns (content, error_msg).
fn cmd_read_input(
  ctx : CommandContext,
  path : String,
  cmd_name : String
) -> (String, String) {
  if path == "-" {
    return (ctx.stdin_content, "")
  }
  let resolved = try {
    @fs.resolve_path(ctx.cwd, path)
  } catch {
    @fs.FsError(msg) => return ("", "\{cmd_name}: \{msg}\n")
  }
  let content = try {
    ctx.fs.read_file(resolved)
  } catch {
    @fs.FsError(msg) => return ("", "\{cmd_name}: \{path}: \{msg}\n")
  }
  (content, "")
}

/// Generate unified diff output using piediff community package.
fn cmd_diff_unified_piediff(
  out : StringBuilder,
  content1 : String,
  content2 : String,
  file1 : String,
  file2 : String
) -> Unit {
  let hunks = @line_diff.line_diff(old=content1[:], new=content2[:])
  if hunks.length() == 0 {
    return
  }
  out.write_string("--- a/\{file1}\n")
  out.write_string("+++ b/\{file2}\n")
  for hunk in hunks {
    let header = hunk.0
    let edits = hunk.1
    out.write_string(header.to_string())
    out.write_char('\n')
    for edit in edits {
      let tag = edit.0
      let text = edit.1
      match tag {
        Eql => out.write_char(' ')
        Del => out.write_char('-')
        Ins => out.write_char('+')
      }
      out.write_stringview(text)
      out.write_char('\n')
    }
  }
}

/// diff: compare two files line by line.
fn cmd_diff(ctx : CommandContext) -> @ast.ExecResult {
  let mut brief = false
  let files : Array[String] = []

  for arg in ctx.args {
    match arg {
      "-u" => ()
      "-q" => brief = true
      _ => files.push(arg)
    }
  }

  if files.length() < 2 {
    return @ast.ExecResult::new(
      stderr="diff: missing operand\n",
      exit_code=2,
    )
  }

  let file1 = files[files.length() - 2]
  let file2 = files[files.length() - 1]

  let (content1, err1) = cmd_read_input(ctx, file1, "diff")
  if err1.length() > 0 {
    return @ast.ExecResult::new(stderr=err1, exit_code=2)
  }
  let (content2, err2) = cmd_read_input(ctx, file2, "diff")
  if err2.length() > 0 {
    return @ast.ExecResult::new(stderr=err2, exit_code=2)
  }

  if content1 == content2 {
    return @ast.ExecResult::new(exit_code=0)
  }

  if brief {
    return @ast.ExecResult::new(
      stdout="Files \{file1} and \{file2} differ\n",
      exit_code=1,
    )
  }

  let out = StringBuilder::new()
  cmd_diff_unified_piediff(out, content1, content2, file1, file2)
  @ast.ExecResult::new(stdout=out.to_string(), exit_code=1)
}

// ============================================================================
// cmp - Compare files byte by byte
// ============================================================================

/// Find first differing byte and line (both 1-based).
/// Returns (byte_pos, line_no, differs_in_common_prefix).
fn cmd_cmp_first_difference(
  content1 : String,
  content2 : String
) -> (Int, Int, Bool) {
  let max_common = if content1.length() < content2.length() {
    content1.length()
  } else {
    content2.length()
  }
  let mut byte_pos = 1
  let mut line_no = 1
  for i = 0; i < max_common; i = i + 1 {
    if content1[i] != content2[i] {
      return (byte_pos, line_no, true)
    }
    if content1[i].to_int().unsafe_to_char() == '\n' {
      line_no += 1
    }
    byte_pos += 1
  }
  (byte_pos, line_no, false)
}

/// cmp: compare two files byte by byte.
/// Supports: -s / --silent / -q
fn cmd_cmp(ctx : CommandContext) -> @ast.ExecResult {
  let mut silent = false
  let mut parsing_options = true
  let files : Array[String] = []

  for arg in ctx.args {
    if parsing_options && arg == "--" {
      parsing_options = false
      continue
    }
    if parsing_options && (arg == "-s" || arg == "--silent" || arg == "-q") {
      silent = true
      continue
    }
    if parsing_options && arg.length() > 1 && arg[0] == '-' {
      return @ast.ExecResult::new(
        stderr="cmp: invalid option -- '\{arg}'\n",
        exit_code=2,
      )
    }
    files.push(arg)
  }

  if files.length() < 2 {
    return @ast.ExecResult::new(
      stderr="cmp: missing operand\n",
      exit_code=2,
    )
  }

  let file1 = files[0]
  let file2 = files[1]

  let (content1, err1) = cmd_read_input(ctx, file1, "cmp")
  if err1.length() > 0 {
    return @ast.ExecResult::new(stderr=err1, exit_code=2)
  }
  let (content2, err2) = cmd_read_input(ctx, file2, "cmp")
  if err2.length() > 0 {
    return @ast.ExecResult::new(stderr=err2, exit_code=2)
  }

  // Use piediff as the canonical equality check for cmp, same as diff.
  let hunks = @line_diff.line_diff(old=content1[:], new=content2[:])
  if hunks.length() == 0 {
    return @ast.ExecResult::new(exit_code=0)
  }

  if silent {
    return @ast.ExecResult::new(exit_code=1)
  }

  let (byte_pos, line_no, differs_in_common_prefix) = cmd_cmp_first_difference(
    content1,
    content2,
  )

  if differs_in_common_prefix {
    return @ast.ExecResult::new(
      stdout="\{file1} \{file2} differ: byte \{byte_pos}, line \{line_no}\n",
      exit_code=1,
    )
  }

  if content1.length() < content2.length() {
    @ast.ExecResult::new(
      stdout="cmp: EOF on \{file1} after byte \{byte_pos}, in line \{line_no}\n",
      exit_code=1,
    )
  } else {
    @ast.ExecResult::new(
      stdout="cmp: EOF on \{file2} after byte \{byte_pos}, in line \{line_no}\n",
      exit_code=1,
    )
  }
}

// ============================================================================
// comm - Compare two sorted files line by line
// ============================================================================

/// comm: compare two sorted files.
fn cmd_comm(ctx : CommandContext) -> @ast.ExecResult {
  let mut suppress1 = false
  let mut suppress2 = false
  let mut suppress3 = false
  let files : Array[String] = []

  for arg in ctx.args {
    if arg.length() > 1 && arg[0] == '-' {
      let mut is_flag = true
      for k = 1; k < arg.length(); k = k + 1 {
        let ch = arg[k].to_int().unsafe_to_char()
        match ch {
          '1' => suppress1 = true
          '2' => suppress2 = true
          '3' => suppress3 = true
          _ => {
            is_flag = false
            break
          }
        }
      }
      if not(is_flag) {
        files.push(arg)
      }
    } else {
      files.push(arg)
    }
  }

  if files.length() < 2 {
    return @ast.ExecResult::err("comm: missing operand\n")
  }

  let (content1, err1) = cmd_read_input(ctx, files[0], "comm")
  if err1.length() > 0 {
    return @ast.ExecResult::err(err1)
  }
  let (content2, err2) = cmd_read_input(ctx, files[1], "comm")
  if err2.length() > 0 {
    return @ast.ExecResult::err(err2)
  }

  let lines1 = cmd_split_lines(content1)
  let lines2 = cmd_split_lines(content2)

  let out = StringBuilder::new()
  let mut i = 0
  let mut j = 0

  while i < lines1.length() && j < lines2.length() {
    let cmp = cmd_find_compare_ascii(lines1[i], lines2[j])
    if cmp < 0 {
      if not(suppress1) {
        out.write_string(lines1[i])
        out.write_char('\n')
      }
      i += 1
    } else if cmp > 0 {
      if not(suppress2) {
        if not(suppress1) {
          out.write_char('\t')
        }
        out.write_string(lines2[j])
        out.write_char('\n')
      }
      j += 1
    } else {
      if not(suppress3) {
        if not(suppress1) {
          out.write_char('\t')
        }
        if not(suppress2) {
          out.write_char('\t')
        }
        out.write_string(lines1[i])
        out.write_char('\n')
      }
      i += 1
      j += 1
    }
  }

  while i < lines1.length() {
    if not(suppress1) {
      out.write_string(lines1[i])
      out.write_char('\n')
    }
    i += 1
  }

  while j < lines2.length() {
    if not(suppress2) {
      if not(suppress1) {
        out.write_char('\t')
      }
      out.write_string(lines2[j])
      out.write_char('\n')
    }
    j += 1
  }

  @ast.ExecResult::ok(out.to_string())
}

// ============================================================================
// base64 - Encode/decode base64
// ============================================================================

/// Encode string to base64 using gmlewis/base64 community package.
fn base64_encode(input : String, wrap_col : Int) -> String {
  let bytes = @base64.str2array(input)
  let fixed : FixedArray[Byte] = FixedArray::make(bytes.length(), b'\x00')
  for i = 0; i < bytes.length(); i = i + 1 {
    fixed[i] = bytes[i]
  }
  let encoded = @base64.std_encode2str(fixed)
  if wrap_col > 0 {
    // Wrap at specified column width
    let out = StringBuilder::new()
    let mut col = 0
    for i = 0; i < encoded.length(); i = i + 1 {
      out.write_char(encoded[i].to_int().unsafe_to_char())
      col += 1
      if col >= wrap_col {
        out.write_char('\n')
        col = 0
      }
    }
    if col > 0 {
      out.write_char('\n')
    }
    out.to_string()
  } else {
    encoded + "\n"
  }
}

/// Decode base64 string using gmlewis/base64 community package.
/// Returns (result, error_msg).
fn base64_decode(input : String) -> (String, String) {
  // Strip whitespace before decoding
  let cleaned = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch != '\n' && ch != '\r' && ch != ' ' && ch != '\t' {
      cleaned.write_char(ch)
    }
  }
  let result = try {
    @base64.std_decode2str(cleaned.to_string())
  } catch {
    _ => return ("", "base64: invalid input\n")
  }
  (result, "")
}

/// base64: encode or decode base64 data.
fn cmd_base64(ctx : CommandContext) -> @ast.ExecResult {
  let mut decode = false
  let mut wrap_col = 76
  let files : Array[String] = []
  let mut i = 0

  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-d" || arg == "--decode" {
      decode = true
      i += 1
    } else if arg == "-w" {
      if i + 1 < ctx.args.length() {
        wrap_col = cmd_parse_int(ctx.args[i + 1])
        i += 2
      } else {
        return @ast.ExecResult::err(
          "base64: option requires an argument -- 'w'\n",
        )
      }
    } else if arg.has_prefix("-w") && arg.length() > 2 {
      wrap_col = cmd_parse_int(cmd_substr_from(arg, 2))
      i += 1
    } else {
      files.push(arg)
      i += 1
    }
  }

  let input = if files.length() > 0 {
    let (content, err) = cmd_read_input(ctx, files[0], "base64")
    if err.length() > 0 {
      return @ast.ExecResult::err(err)
    }
    content
  } else {
    ctx.stdin_content
  }

  if decode {
    let (result, err) = base64_decode(input)
    if err.length() > 0 {
      return @ast.ExecResult::err(err)
    }
    @ast.ExecResult::ok(result)
  } else {
    @ast.ExecResult::ok(base64_encode(input, wrap_col))
  }
}

// ============================================================================
// expr - Expression evaluator (POSIX)
// ============================================================================

/// Expr parser state. Uses mutable error field instead of exceptions.
priv struct ExprParser {
  tokens : Array[String]
  mut pos : Int
  mut error : String
}

fn ExprParser::new(tokens : Array[String]) -> ExprParser {
  { tokens, pos: 0, error: "" }
}

fn ExprParser::peek(self : ExprParser) -> String? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

fn ExprParser::advance(self : ExprParser) -> String? {
  if self.pos < self.tokens.length() {
    let tok = self.tokens[self.pos]
    self.pos += 1
    Some(tok)
  } else {
    None
  }
}

fn ExprParser::has_error(self : ExprParser) -> Bool {
  self.error.length() > 0
}

fn ExprParser::set_error(self : ExprParser, msg : String) -> Unit {
  if self.error.length() == 0 {
    self.error = msg
  }
}

/// Try to parse a string as integer.
fn expr_try_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut start = 0
  let mut neg = false
  if s[0] == '-' {
    neg = true
    start = 1
  } else if s[0] == '+' {
    start = 1
  }
  if start >= s.length() {
    return None
  }
  let mut result = 0
  for i = start; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - 48)
    } else {
      return None
    }
  }
  if neg { Some(-result) } else { Some(result) }
}

/// Check if expr result is "truthy".
fn expr_is_truthy(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  match expr_try_int(s) {
    Some(n) => n != 0
    None => true
  }
}

/// Parse or-expression: expr1 '|' expr2
fn expr_parse_or(p : ExprParser) -> String {
  let mut left = expr_parse_and(p)
  if p.has_error() {
    return left
  }
  while p.peek() == Some("|") {
    ignore(p.advance())
    let right = expr_parse_and(p)
    if p.has_error() {
      return left
    }
    left = if expr_is_truthy(left) { left } else { right }
  }
  left
}

/// Parse and-expression: expr1 '&' expr2
fn expr_parse_and(p : ExprParser) -> String {
  let mut left = expr_parse_comparison(p)
  if p.has_error() {
    return left
  }
  while p.peek() == Some("&") {
    ignore(p.advance())
    let right = expr_parse_comparison(p)
    if p.has_error() {
      return left
    }
    left = if expr_is_truthy(left) && expr_is_truthy(right) {
      left
    } else {
      "0"
    }
  }
  left
}

/// Parse comparison.
fn expr_parse_comparison(p : ExprParser) -> String {
  let mut left = expr_parse_add(p)
  if p.has_error() {
    return left
  }
  while true {
    match p.peek() {
      Some(op) => {
        if op == "=" || op == "!=" || op == "<" || op == "<=" || op == ">" ||
          op == ">=" {
          ignore(p.advance())
          let right = expr_parse_add(p)
          if p.has_error() {
            return left
          }
          let result = match (expr_try_int(left), expr_try_int(right)) {
            (Some(l), Some(r)) =>
              if op == "=" {
                l == r
              } else if op == "!=" {
                l != r
              } else if op == "<" {
                l < r
              } else if op == "<=" {
                l <= r
              } else if op == ">" {
                l > r
              } else {
                l >= r
              }
            _ =>
              if op == "=" {
                left == right
              } else if op == "!=" {
                left != right
              } else if op == "<" {
                cmd_find_compare_ascii(left, right) < 0
              } else if op == "<=" {
                cmd_find_compare_ascii(left, right) <= 0
              } else if op == ">" {
                cmd_find_compare_ascii(left, right) > 0
              } else {
                cmd_find_compare_ascii(left, right) >= 0
              }
          }
          left = if result { "1" } else { "0" }
        } else {
          break
        }
      }
      None => break
    }
  }
  left
}

/// Parse addition/subtraction.
fn expr_parse_add(p : ExprParser) -> String {
  let mut left = expr_parse_mul(p)
  if p.has_error() {
    return left
  }
  while true {
    match p.peek() {
      Some(op) => {
        if op == "+" || op == "-" {
          ignore(p.advance())
          let right = expr_parse_mul(p)
          if p.has_error() {
            return left
          }
          let l = match expr_try_int(left) {
            Some(n) => n
            None => {
              p.set_error("expr: non-integer argument\n")
              return "0"
            }
          }
          let r = match expr_try_int(right) {
            Some(n) => n
            None => {
              p.set_error("expr: non-integer argument\n")
              return "0"
            }
          }
          left = if op == "+" {
            (l + r).to_string()
          } else {
            (l - r).to_string()
          }
        } else {
          break
        }
      }
      None => break
    }
  }
  left
}

/// Parse multiplication/division/modulo.
fn expr_parse_mul(p : ExprParser) -> String {
  let mut left = expr_parse_primary(p)
  if p.has_error() {
    return left
  }
  while true {
    match p.peek() {
      Some(op) => {
        if op == "*" || op == "/" || op == "%" {
          ignore(p.advance())
          let right = expr_parse_primary(p)
          if p.has_error() {
            return left
          }
          let l = match expr_try_int(left) {
            Some(n) => n
            None => {
              p.set_error("expr: non-integer argument\n")
              return "0"
            }
          }
          let r = match expr_try_int(right) {
            Some(n) => n
            None => {
              p.set_error("expr: non-integer argument\n")
              return "0"
            }
          }
          if op == "*" {
            left = (l * r).to_string()
          } else if op == "/" {
            if r == 0 {
              p.set_error("expr: division by zero\n")
              return "0"
            }
            left = (l / r).to_string()
          } else {
            if r == 0 {
              p.set_error("expr: division by zero\n")
              return "0"
            }
            left = (l % r).to_string()
          }
        } else {
          break
        }
      }
      None => break
    }
  }
  left
}

/// Parse primary: parenthesized expr, string functions, or atom.
fn expr_parse_primary(p : ExprParser) -> String {
  if p.has_error() {
    return "0"
  }
  match p.peek() {
    None => {
      p.set_error("expr: syntax error\n")
      "0"
    }
    Some(tok) => {
      if tok == "(" {
        ignore(p.advance())
        let result = expr_parse_or(p)
        if p.has_error() {
          return result
        }
        match p.advance() {
          Some(")") => result
          _ => {
            p.set_error("expr: syntax error\n")
            result
          }
        }
      } else if tok == "length" {
        ignore(p.advance())
        match p.advance() {
          Some(v) => v.length().to_string()
          None => {
            p.set_error("expr: syntax error\n")
            "0"
          }
        }
      } else if tok == "substr" {
        ignore(p.advance())
        let s = match p.advance() {
          Some(v) => v
          None => {
            p.set_error("expr: syntax error\n")
            return "0"
          }
        }
        let pos_s = match p.advance() {
          Some(v) => v
          None => {
            p.set_error("expr: syntax error\n")
            return "0"
          }
        }
        let len_s = match p.advance() {
          Some(v) => v
          None => {
            p.set_error("expr: syntax error\n")
            return "0"
          }
        }
        let pos = match expr_try_int(pos_s) {
          Some(n) => n
          None => {
            p.set_error("expr: non-integer argument\n")
            return "0"
          }
        }
        let len = match expr_try_int(len_s) {
          Some(n) => n
          None => {
            p.set_error("expr: non-integer argument\n")
            return "0"
          }
        }
        let start = if pos < 1 { 0 } else { pos - 1 }
        let end_ = start + len
        cmd_substr_slice(s, start, end_)
      } else if tok == "match" {
        ignore(p.advance())
        let _s = match p.advance() {
          Some(v) => v
          None => {
            p.set_error("expr: syntax error\n")
            return "0"
          }
        }
        let _pat = match p.advance() {
          Some(v) => v
          None => {
            p.set_error("expr: syntax error\n")
            return "0"
          }
        }
        "0"
      } else {
        // Atom
        ignore(p.advance())
        match p.peek() {
          Some(":") => {
            ignore(p.advance())
            let _pat = match p.advance() {
              Some(v) => v
              None => {
                p.set_error("expr: syntax error\n")
                return "0"
              }
            }
            "0"
          }
          _ => tok
        }
      }
    }
  }
}

/// expr: evaluate expression.
fn cmd_expr(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    return @ast.ExecResult::new(
      stderr="expr: missing operand\n",
      exit_code=2,
    )
  }

  let parser = ExprParser::new(ctx.args)
  let result = expr_parse_or(parser)

  if parser.has_error() {
    return @ast.ExecResult::new(stderr=parser.error, exit_code=2)
  }

  if parser.pos < parser.tokens.length() {
    return @ast.ExecResult::new(
      stderr="expr: syntax error\n",
      exit_code=2,
    )
  }

  let exit_code = if expr_is_truthy(result) { 0 } else { 1 }
  @ast.ExecResult::new(stdout=result + "\n", exit_code=exit_code)
}
