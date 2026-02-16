// MoonBash Commands - Text/Data Processing Extensions
// diff, comm, base64, expr

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

/// Compute LCS table for two arrays of lines.
fn cmd_diff_lcs_table(
  a : Array[String],
  b : Array[String]
) -> Array[Array[Int]] {
  let m = a.length()
  let n = b.length()
  let dp : Array[Array[Int]] = Array::new(capacity=m + 1)
  for i = 0; i <= m; i = i + 1 {
    let row : Array[Int] = Array::new(capacity=n + 1)
    for j = 0; j <= n; j = j + 1 {
      row.push(0)
    }
    dp.push(row)
  }
  for i = 1; i <= m; i = i + 1 {
    for j = 1; j <= n; j = j + 1 {
      if a[i - 1] == b[j - 1] {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else if dp[i - 1][j] >= dp[i][j - 1] {
        dp[i][j] = dp[i - 1][j]
      } else {
        dp[i][j] = dp[i][j - 1]
      }
    }
  }
  dp
}

/// Tag each line: ' ' = common, '-' = only in a, '+' = only in b.
fn cmd_diff_backtrack(
  dp : Array[Array[Int]],
  a : Array[String],
  b : Array[String]
) -> Array[(Char, String)] {
  let result : Array[(Char, String)] = []
  let mut i = a.length()
  let mut j = b.length()
  while i > 0 || j > 0 {
    if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
      result.push((' ', a[i - 1]))
      i -= 1
      j -= 1
    } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
      result.push(('+', b[j - 1]))
      j -= 1
    } else {
      result.push(('-', a[i - 1]))
      i -= 1
    }
  }
  // Reverse in place
  let mut lo = 0
  let mut hi = result.length() - 1
  while lo < hi {
    let tmp = result[lo]
    result[lo] = result[hi]
    result[hi] = tmp
    lo += 1
    hi -= 1
  }
  result
}

/// Generate unified diff hunks from tagged lines.
fn cmd_diff_unified(
  out : StringBuilder,
  tagged : Array[(Char, String)],
  file1 : String,
  file2 : String
) -> Unit {
  let context = 3
  let len = tagged.length()

  // Find ranges of changed lines
  let change_starts : Array[Int] = []
  let change_ends : Array[Int] = []
  let mut k = 0
  while k < len {
    let (tag, _) = tagged[k]
    if tag != ' ' {
      let start = k
      while k < len {
        let (t, _) = tagged[k]
        if t == ' ' {
          break
        }
        k += 1
      }
      change_starts.push(start)
      change_ends.push(k)
    } else {
      k += 1
    }
  }

  if change_starts.length() == 0 {
    return
  }

  out.write_string("--- a/\{file1}\n")
  out.write_string("+++ b/\{file2}\n")

  // Group changes into hunks
  let mut ci = 0
  while ci < change_starts.length() {
    let hunk_start = {
      let s = change_starts[ci] - context
      if s < 0 { 0 } else { s }
    }
    let mut hunk_end = {
      let e = change_ends[ci] + context
      if e > len { len } else { e }
    }
    let mut ci_end = ci
    while ci_end + 1 < change_starts.length() {
      let next_start = change_starts[ci_end + 1] - context
      if next_start <= hunk_end {
        ci_end += 1
        let e = change_ends[ci_end] + context
        hunk_end = if e > len { len } else { e }
      } else {
        break
      }
    }

    let mut a_start = 0
    let mut b_start = 0
    for t = 0; t < hunk_start; t = t + 1 {
      let (tag, _) = tagged[t]
      if tag == ' ' || tag == '-' {
        a_start += 1
      }
      if tag == ' ' || tag == '+' {
        b_start += 1
      }
    }
    let mut a_count = 0
    let mut b_count = 0
    for t = hunk_start; t < hunk_end; t = t + 1 {
      let (tag, _) = tagged[t]
      if tag == ' ' || tag == '-' {
        a_count += 1
      }
      if tag == ' ' || tag == '+' {
        b_count += 1
      }
    }

    out.write_string(
      "@@ -\{a_start + 1},\{a_count} +\{b_start + 1},\{b_count} @@\n",
    )

    for t = hunk_start; t < hunk_end; t = t + 1 {
      let (tag, line) = tagged[t]
      out.write_char(tag)
      out.write_string(line)
      out.write_char('\n')
    }

    ci = ci_end + 1
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

  let lines1 = cmd_split_lines(content1)
  let lines2 = cmd_split_lines(content2)
  let dp = cmd_diff_lcs_table(lines1, lines2)
  let tagged = cmd_diff_backtrack(dp, lines1, lines2)

  let out = StringBuilder::new()
  cmd_diff_unified(out, tagged, file1, file2)
  @ast.ExecResult::new(stdout=out.to_string(), exit_code=1)
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

let base64_chars : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

/// Get base64 character index (decode table).
fn base64_decode_char(ch : Char) -> Int {
  if ch >= 'A' && ch <= 'Z' {
    ch.to_int() - 65
  } else if ch >= 'a' && ch <= 'z' {
    ch.to_int() - 97 + 26
  } else if ch >= '0' && ch <= '9' {
    ch.to_int() - 48 + 52
  } else if ch == '+' {
    62
  } else if ch == '/' {
    63
  } else {
    -1
  }
}

/// Encode string to base64.
fn base64_encode(input : String, wrap_col : Int) -> String {
  let out = StringBuilder::new()
  let len = input.length()
  let mut i = 0
  let mut col = 0

  while i < len {
    let b0 = input[i].to_int() & 0xFF
    let b1 = if i + 1 < len { input[i + 1].to_int() & 0xFF } else { 0 }
    let b2 = if i + 2 < len { input[i + 2].to_int() & 0xFF } else { 0 }
    let remaining = len - i

    let c0 = (b0 >> 2) & 0x3F
    let c1 = ((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0F)
    let c2 = ((b1 & 0x0F) << 2) | ((b2 >> 6) & 0x03)
    let c3 = b2 & 0x3F

    out.write_char(base64_chars[c0].to_int().unsafe_to_char())
    out.write_char(base64_chars[c1].to_int().unsafe_to_char())
    if remaining > 1 {
      out.write_char(base64_chars[c2].to_int().unsafe_to_char())
    } else {
      out.write_char('=')
    }
    if remaining > 2 {
      out.write_char(base64_chars[c3].to_int().unsafe_to_char())
    } else {
      out.write_char('=')
    }

    col += 4
    if wrap_col > 0 && col >= wrap_col {
      out.write_char('\n')
      col = 0
    }

    i += 3
  }

  if wrap_col > 0 && col > 0 {
    out.write_char('\n')
  } else if wrap_col == 0 {
    out.write_char('\n')
  }

  out.to_string()
}

/// Decode base64 string. Returns (result, error_msg).
fn base64_decode(input : String) -> (String, String) {
  let chars : Array[Int] = []
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '=' {
      break
    }
    let val = base64_decode_char(ch)
    if val >= 0 {
      chars.push(val)
    } else if ch != '\n' && ch != '\r' && ch != ' ' && ch != '\t' {
      return ("", "base64: invalid input\n")
    }
  }

  let out = StringBuilder::new()
  let len = chars.length()
  let mut i = 0
  while i < len {
    let c0 = chars[i]
    let c1 = if i + 1 < len { chars[i + 1] } else { 0 }
    let c2 = if i + 2 < len { chars[i + 2] } else { 0 }
    let c3 = if i + 3 < len { chars[i + 3] } else { 0 }

    let b0 = (c0 << 2) | ((c1 >> 4) & 0x03)
    out.write_char((b0 & 0xFF).unsafe_to_char())

    if i + 2 < len {
      let b1 = ((c1 & 0x0F) << 4) | ((c2 >> 2) & 0x0F)
      out.write_char((b1 & 0xFF).unsafe_to_char())
    }

    if i + 3 < len {
      let b2 = ((c2 & 0x03) << 6) | c3
      out.write_char((b2 & 0xFF).unsafe_to_char())
    }

    i += 4
  }

  (out.to_string(), "")
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
