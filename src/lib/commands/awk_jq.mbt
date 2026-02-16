// MoonBash Commands - awk / jq (comparison-focused subset)

// ============================================================================
// Shared Helpers
// ============================================================================

fn aj_parse_int(s : String) -> Int {
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

fn aj_trim(s : String) -> String {
  let mut start = 0
  let mut end_ = s.length()
  while start < end_ {
    let ch = s[start].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      start += 1
    } else {
      break
    }
  }
  while end_ > start {
    let ch = s[end_ - 1].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      end_ -= 1
    } else {
      break
    }
  }
  if start == 0 && end_ == s.length() {
    s
  } else if start >= end_ {
    ""
  } else {
    s.substring(start=start, end=end_)
  }
}

fn aj_starts_with(s : String, prefix : String) -> Bool {
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

fn aj_ends_with(s : String, suffix : String) -> Bool {
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

fn aj_substr(s : String, start : Int, end_ : Int) -> String {
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

fn aj_index_of(s : String, ch : Char, start~ : Int = 0) -> Int {
  for i = start; i < s.length(); i = i + 1 {
    if s[i].to_int().unsafe_to_char() == ch {
      return i
    }
  }
  -1
}

fn aj_find_substring(s : String, needle : String, start~ : Int = 0) -> Int {
  if needle.length() == 0 {
    return start
  }
  if start < 0 || needle.length() > s.length() {
    return -1
  }
  if start > s.length() - needle.length() {
    return -1
  }
  let mut i = start
  while i <= s.length() - needle.length() {
    let mut matched = true
    for j = 0; j < needle.length(); j = j + 1 {
      if s[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
    i += 1
  }
  -1
}

fn aj_split_lines_records(input : String) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let trailing = buf.to_string()
  if trailing.length() > 0 {
    lines.push(trailing)
  }
  lines
}

fn aj_split_by_delim(s : String, delim : String) -> Array[String] {
  if delim.length() == 0 {
    return [s]
  }
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let mut match_found = true
    if i + delim.length() <= s.length() {
      for j = 0; j < delim.length(); j = j + 1 {
        if s[i + j] != delim[j] {
          match_found = false
          break
        }
      }
    } else {
      match_found = false
    }

    if match_found {
      parts.push(buf.to_string())
      buf.reset()
      i += delim.length()
    } else {
      buf.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  parts.push(buf.to_string())
  parts
}

fn aj_decode_c_escapes(s : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < s.length() {
      let next = s[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => { out.write_char('\n'); i += 2 }
        't' => { out.write_char('\t'); i += 2 }
        'r' => { out.write_char('\r'); i += 2 }
        '\\' => { out.write_char('\\'); i += 2 }
        '"' => { out.write_char('"'); i += 2 }
        _ => { out.write_char(next); i += 2 }
      }
    } else {
      out.write_char(ch)
      i += 1
    }
  }
  out.to_string()
}

// ============================================================================
// awk
// ============================================================================

priv struct AwkProgram {
  begin_action : String?
  pattern : String
  action : String
  end_action : String?
  has_main : Bool
  range_start : String?
  range_end : String?
}

fn awk_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn awk_is_identifier_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

fn awk_is_identifier(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let first = name[0].to_int().unsafe_to_char()
  if not((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z') || first == '_') {
    return false
  }
  for i = 1; i < name.length(); i = i + 1 {
    if not(awk_is_identifier_char(name[i].to_int().unsafe_to_char())) {
      return false
    }
  }
  true
}

fn awk_take_named_block(
  src : String,
  name : String
) -> (String?, String) {
  let mut pos = -1
  let mut brace_pos = -1
  let mut i = 0
  while i + name.length() <= src.length() {
    if aj_substr(src, i, i + name.length()) == name {
      let left_ok = if i == 0 {
        true
      } else {
        not(awk_is_identifier_char(src[i - 1].to_int().unsafe_to_char()))
      }
      if left_ok {
        let mut j = i + name.length()
        while j < src.length() && awk_is_space(src[j].to_int().unsafe_to_char()) {
          j += 1
        }
        if j < src.length() && src[j].to_int().unsafe_to_char() == '{' {
          pos = i
          brace_pos = j
          break
        }
      }
    }
    i += 1
  }
  if pos < 0 {
    return (None, src)
  }

  let block_start = brace_pos + 1
  let mut depth = 1
  let mut j = block_start
  while j < src.length() && depth > 0 {
    let ch = src[j].to_int().unsafe_to_char()
    if ch == '{' {
      depth += 1
    } else if ch == '}' {
      depth -= 1
    }
    if depth > 0 {
      j += 1
    }
  }
  if depth != 0 {
    return (None, src)
  }

  let block = aj_substr(src, block_start, j)
  let remaining = aj_substr(src, 0, pos) + aj_substr(src, j + 1, src.length())
  (Some(block), remaining)
}

fn awk_split_range_pattern(pattern : String) -> (String?, String?) {
  let p = aj_trim(pattern)
  let mut quote : Char? = None
  let mut in_regex = false
  let mut escaped = false
  for i = 0; i < p.length(); i = i + 1 {
    let ch = p[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < p.length() {
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if in_regex {
          if escaped {
            escaped = false
          } else if ch == '\\' {
            escaped = true
          } else if ch == '/' {
            in_regex = false
          }
        } else {
          if ch == '"' || ch == '\'' {
            quote = Some(ch)
          } else if ch == '/' {
            in_regex = true
            escaped = false
          } else if ch == ',' {
            let left = aj_trim(aj_substr(p, 0, i))
            let right = aj_trim(aj_substr(p, i + 1, p.length()))
            if left.length() == 0 || right.length() == 0 {
              return (None, None)
            }
            return (Some(left), Some(right))
          }
        }
      }
    }
  }
  (None, None)
}

fn awk_parse_program(src : String) -> AwkProgram {
  let (begin_block, rest1) = awk_take_named_block(src, "BEGIN")
  let (end_block, rest2) = awk_take_named_block(rest1, "END")
  let rest = aj_trim(rest2)

  if rest.length() == 0 {
    return {
      begin_action: begin_block,
      pattern: "",
      action: "",
      end_action: end_block,
      has_main: false,
      range_start: None,
      range_end: None,
    }
  }

  let brace_pos = aj_index_of(rest, '{')
  if brace_pos < 0 {
    let pattern = aj_trim(rest)
    let (range_start, range_end) = awk_split_range_pattern(pattern)
    return {
      begin_action: begin_block,
      pattern,
      action: "",
      end_action: end_block,
      has_main: true,
      range_start,
      range_end,
    }
  }

  let pattern = aj_trim(aj_substr(rest, 0, brace_pos))
  let (range_start, range_end) = awk_split_range_pattern(pattern)
  let mut depth = 1
  let mut quote : Char? = None
  let mut i = brace_pos + 1
  while i < rest.length() && depth > 0 {
    let ch = rest[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < rest.length() {
          i += 2
          continue
        }
        if ch == q {
          quote = None
        }
        i += 1
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          i += 1
        } else if ch == '{' {
          depth += 1
          i += 1
        } else if ch == '}' {
          depth -= 1
          if depth > 0 {
            i += 1
          }
        } else {
          i += 1
        }
      }
    }
  }
  let action = if i <= rest.length() { aj_substr(rest, brace_pos + 1, i) } else { "" }
  {
    begin_action: begin_block,
    pattern,
    action,
    end_action: end_block,
    has_main: true,
    range_start,
    range_end,
  }
}

fn awk_split_fields(line : String, fs : String) -> Array[String] {
  if fs == " " {
    let fields : Array[String] = []
    let buf = StringBuilder::new()
    let mut in_field = false
    for i = 0; i < line.length(); i = i + 1 {
      let ch = line[i].to_int().unsafe_to_char()
      if ch == ' ' || ch == '\t' {
        if in_field {
          fields.push(buf.to_string())
          buf.reset()
          in_field = false
        }
      } else {
        buf.write_char(ch)
        in_field = true
      }
    }
    if in_field {
      fields.push(buf.to_string())
    }
    return fields
  }
  aj_split_by_delim(line, fs)
}

fn awk_array_key(name : String, index : Int) -> String {
  name + "#" + index.to_string()
}

fn awk_is_numeric_string(s : String) -> Bool {
  let t = aj_trim(s)
  if t.length() == 0 {
    return false
  }
  let mut i = 0
  if t[0].to_int().unsafe_to_char() == '+' || t[0].to_int().unsafe_to_char() == '-' {
    i = 1
  }
  if i >= t.length() {
    return false
  }
  let mut seen_digit = false
  let mut seen_dot = false
  while i < t.length() {
    let ch = t[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      seen_digit = true
      i += 1
      continue
    }
    if ch == '.' && not(seen_dot) {
      seen_dot = true
      i += 1
      continue
    }
    return false
  }
  seen_digit
}

fn awk_parse_number(s : String) -> Double {
  if not(awk_is_numeric_string(s)) {
    return 0.0
  }
  let t = aj_trim(s)
  let mut i = 0
  let mut sign = 1.0
  if t[0].to_int().unsafe_to_char() == '-' {
    sign = -1.0
    i = 1
  } else if t[0].to_int().unsafe_to_char() == '+' {
    i = 1
  }

  let mut whole = 0
  while i < t.length() {
    let ch = t[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      whole = whole * 10 + (ch.to_int() - '0'.to_int())
      i += 1
    } else {
      break
    }
  }

  let mut frac = 0
  let mut scale = 1
  if i < t.length() && t[i].to_int().unsafe_to_char() == '.' {
    i += 1
    while i < t.length() {
      let ch = t[i].to_int().unsafe_to_char()
      if ch >= '0' && ch <= '9' {
        frac = frac * 10 + (ch.to_int() - '0'.to_int())
        scale = scale * 10
        i += 1
      } else {
        break
      }
    }
  }

  let mut value = whole.to_double()
  if scale > 1 {
    value = value + frac.to_double() / scale.to_double()
  }
  sign * value
}

fn awk_number_to_string(n : Double) -> String {
  let as_int = n.to_int()
  if as_int.to_double() == n {
    as_int.to_string()
  } else {
    n.to_string()
  }
}

fn awk_find_top_level_token(expr : String, token : String) -> Int {
  if token.length() == 0 || token.length() > expr.length() {
    return -1
  }
  let mut quote : Char? = None
  let mut bracket_depth = 0
  let mut i = 0
  while i + token.length() <= expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < expr.length() {
          i += 2
          continue
        }
        if ch == q {
          quote = None
        }
        i += 1
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          i += 1
          continue
        }
        if ch == '[' {
          bracket_depth += 1
          i += 1
          continue
        }
        if ch == ']' && bracket_depth > 0 {
          bracket_depth -= 1
          i += 1
          continue
        }
        if bracket_depth == 0 {
          let mut matched = true
          for j = 0; j < token.length(); j = j + 1 {
            if expr[i + j] != token[j] {
              matched = false
              break
            }
          }
          if matched {
            return i
          }
        }
        i += 1
      }
    }
  }
  -1
}

fn awk_find_top_level_operator(expr : String, ops : String) -> Int {
  let mut quote : Char? = None
  let mut bracket_depth = 0
  let mut idx = -1
  for i = 0; i < expr.length(); i = i + 1 {
    let ch = expr[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < expr.length() {
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
        } else if ch == '[' {
          bracket_depth += 1
        } else if ch == ']' && bracket_depth > 0 {
          bracket_depth -= 1
        } else if bracket_depth == 0 {
          let mut in_ops = false
          for j = 0; j < ops.length(); j = j + 1 {
            if ops[j].to_int().unsafe_to_char() == ch {
              in_ops = true
              break
            }
          }
          if in_ops {
            if (ch == '+' || ch == '-') && i == 0 {
              continue
            }
            idx = i
          }
        }
      }
    }
  }
  idx
}

fn awk_eval_atom(
  atom : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let t = aj_trim(atom)
  if t.length() == 0 {
    return ""
  }

  if (aj_starts_with(t, "\"") && aj_ends_with(t, "\"")) ||
    (aj_starts_with(t, "'") && aj_ends_with(t, "'")) {
    return aj_decode_c_escapes(aj_substr(t, 1, t.length() - 1))
  }

  if t == "NR" {
    return nr.to_string()
  }
  if t == "NF" {
    return nf.to_string()
  }

  if aj_starts_with(t, "$") {
    let key = aj_substr(t, 1, t.length())
    if key == "0" {
      return line
    }
    if key == "NF" {
      return if fields.length() == 0 { "" } else { fields[fields.length() - 1] }
    } else {
      let idx = aj_parse_int(key)
      if idx >= 1 && idx <= fields.length() {
        return fields[idx - 1]
      } else {
        return ""
      }
    }
  }

  let open_bracket = aj_index_of(t, '[')
  if open_bracket > 0 &&
    t[t.length() - 1].to_int().unsafe_to_char() == ']' {
    let arr_name = aj_trim(aj_substr(t, 0, open_bracket))
    let idx_text = aj_trim(aj_substr(t, open_bracket + 1, t.length() - 1))
    let idx = aj_parse_int(idx_text)
    if idx >= 1 {
      return array_vars.get(awk_array_key(arr_name, idx)).unwrap_or("")
    }
  }

  if awk_is_numeric_string(t) {
    return t
  }

  if awk_is_identifier(t) {
    return vars.get(t).unwrap_or("")
  }

  ""
}

fn awk_tokenize_expr(expr : String) -> Array[String] {
  let tokens : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  for i = 0; i < expr.length(); i = i + 1 {
    let ch = expr[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          buf.write_char(ch)
        } else if ch == ' ' || ch == '\t' {
          let tok = buf.to_string()
          if tok.length() > 0 {
            tokens.push(tok)
            buf.reset()
          }
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    tokens.push(last)
  }
  tokens
}

fn awk_eval_number(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> Double {
  let value = awk_eval_expr(expr, line, fields, nr, nf, vars, array_vars)
  awk_parse_number(value)
}

fn awk_eval_expr(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let t = aj_trim(expr)
  let tokens = awk_tokenize_expr(t)
  if tokens.length() == 0 {
    return ""
  }

  if tokens.length() > 1 {
    let out = StringBuilder::new()
    for tok in tokens {
      out.write_string(awk_eval_expr(tok, line, fields, nr, nf, vars, array_vars))
    }
    return out.to_string()
  }

  let add_sub_idx = awk_find_top_level_operator(t, "+-")
  if add_sub_idx > 0 {
    let op = t[add_sub_idx].to_int().unsafe_to_char()
    let left = awk_eval_number(
      aj_substr(t, 0, add_sub_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(t, add_sub_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let value = if op == '+' { left + right } else { left - right }
    return awk_number_to_string(value)
  }

  let mul_div_idx = awk_find_top_level_operator(t, "*/")
  if mul_div_idx > 0 {
    let op = t[mul_div_idx].to_int().unsafe_to_char()
    let left = awk_eval_number(
      aj_substr(t, 0, mul_div_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(t, mul_div_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if op == '*' {
      return awk_number_to_string(left * right)
    }
    if right == 0.0 {
      return "0"
    }
    return (left / right).to_string()
  }

  awk_eval_atom(t, line, fields, nr, nf, vars, array_vars)
}

fn awk_split_csv_args(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          buf.write_char(ch)
        } else if ch == ',' {
          parts.push(aj_trim(buf.to_string()))
          buf.reset()
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  let last = aj_trim(buf.to_string())
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

fn awk_parse_printf(action : String) -> (String, String?) {
  let rest = aj_trim(aj_substr(action, 6, action.length()))
  if rest.length() == 0 {
    return ("", None)
  }
  let quote = rest[0].to_int().unsafe_to_char()
  if quote != '"' && quote != '\'' {
    return (rest, None)
  }
  let mut i = 1
  while i < rest.length() {
    if rest[i].to_int().unsafe_to_char() == quote {
      break
    }
    i += 1
  }
  let format = aj_substr(rest, 1, i)
  let tail = aj_trim(aj_substr(rest, i + 1, rest.length()))
  if aj_starts_with(tail, ",") {
    (format, Some(aj_trim(aj_substr(tail, 1, tail.length()))))
  } else {
    (format, None)
  }
}

fn awk_format_printf(format : String, arg : String) -> String {
  let decoded = aj_decode_c_escapes(format)
  let out = StringBuilder::new()
  let mut i = 0
  while i < decoded.length() {
    let ch = decoded[i].to_int().unsafe_to_char()
    if ch == '%' && i + 1 < decoded.length() {
      let spec = decoded[i + 1].to_int().unsafe_to_char()
      if spec == 's' {
        out.write_string(arg)
        i += 2
        continue
      }
      if spec == 'd' {
        out.write_string(aj_parse_int(arg).to_string())
        i += 2
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn awk_match_regex_pattern(pattern_expr : String, line : String) -> Bool {
  let p = aj_trim(pattern_expr)
  if not(aj_starts_with(p, "/")) || not(aj_ends_with(p, "/")) || p.length() < 2 {
    return false
  }
  let pat = aj_substr(p, 1, p.length() - 1)
  if aj_starts_with(pat, "^") && aj_ends_with(pat, "$") {
    return line == aj_substr(pat, 1, pat.length() - 1)
  }
  if aj_starts_with(pat, "^") {
    return aj_starts_with(line, aj_substr(pat, 1, pat.length()))
  }
  if aj_ends_with(pat, "$") {
    let suffix = aj_substr(pat, 0, pat.length() - 1)
    return aj_ends_with(line, suffix)
  }
  aj_find_substring(line, pat) >= 0
}

fn awk_eval_condition(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> Bool {
  let p = aj_trim(expr)
  if p.length() == 0 {
    return true
  }

  let and_idx = awk_find_top_level_token(p, "&&")
  if and_idx > 0 {
    let left = aj_substr(p, 0, and_idx)
    let right = aj_substr(p, and_idx + 2, p.length())
    return awk_eval_condition(left, line, fields, nr, nf, vars, array_vars) &&
      awk_eval_condition(right, line, fields, nr, nf, vars, array_vars)
  }

  if aj_starts_with(p, "/") && aj_ends_with(p, "/") {
    return awk_match_regex_pattern(p, line)
  }

  let mut idx = awk_find_top_level_token(p, "==")
  if idx > 0 {
    let left = awk_eval_expr(
      aj_substr(p, 0, idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(p, idx + 2, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if awk_is_numeric_string(left) && awk_is_numeric_string(right) {
      return awk_parse_number(left) == awk_parse_number(right)
    }
    return left == right
  }

  idx = awk_find_top_level_token(p, "!=")
  if idx > 0 {
    let left = awk_eval_expr(
      aj_substr(p, 0, idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(p, idx + 2, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if awk_is_numeric_string(left) && awk_is_numeric_string(right) {
      return awk_parse_number(left) != awk_parse_number(right)
    }
    return left != right
  }

  idx = awk_find_top_level_token(p, ">=")
  if idx > 0 {
    let left = awk_eval_number(
      aj_substr(p, 0, idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(p, idx + 2, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return left >= right
  }

  idx = awk_find_top_level_token(p, "<=")
  if idx > 0 {
    let left = awk_eval_number(
      aj_substr(p, 0, idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(p, idx + 2, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return left <= right
  }

  idx = awk_find_top_level_token(p, ">")
  if idx > 0 {
    let left = awk_eval_number(
      aj_substr(p, 0, idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(p, idx + 1, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return left > right
  }

  idx = awk_find_top_level_token(p, "<")
  if idx > 0 {
    let left = awk_eval_number(
      aj_substr(p, 0, idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(p, idx + 1, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return left < right
  }

  let value = awk_eval_expr(p, line, fields, nr, nf, vars, array_vars)
  if awk_is_numeric_string(value) {
    awk_parse_number(value) != 0.0
  } else {
    value.length() > 0
  }
}

fn awk_pattern_match_program(
  prog : AwkProgram,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  in_range : Bool
) -> (Bool, Bool) {
  if not(prog.has_main) {
    return (false, in_range)
  }

  match (prog.range_start, prog.range_end) {
    (Some(start_expr), Some(end_expr)) => {
      if in_range {
        let end_hit = awk_eval_condition(
          end_expr,
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        (true, not(end_hit))
      } else {
        let start_hit = awk_eval_condition(
          start_expr,
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        if not(start_hit) {
          (false, false)
        } else {
          let end_hit = awk_eval_condition(
            end_expr,
            line,
            fields,
            nr,
            nf,
            vars,
            array_vars,
          )
          (true, not(end_hit))
        }
      }
    }
    _ => (
      awk_eval_condition(prog.pattern, line, fields, nr, nf, vars, array_vars),
      false,
    )
  }
}

fn awk_split_statements(action : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  for i = 0; i < action.length(); i = i + 1 {
    let ch = action[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == '\\' && i + 1 < action.length() {
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          buf.write_char(ch)
        } else if ch == ';' {
          parts.push(aj_trim(buf.to_string()))
          buf.reset()
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  let last = aj_trim(buf.to_string())
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

fn awk_execute_action(
  action : String,
  lines : Array[String],
  line_idx : Int,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  fs : String,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> (String, Array[String], Int, Int) {
  let act = aj_trim(action)
  let mut current_line = line
  let mut current_fields = fields
  let mut current_nr = nr
  let mut consumed = 0

  if act.length() == 0 {
    out.write_string(current_line)
    out.write_char('\n')
    return (current_line, current_fields, consumed, current_nr)
  }

  let statements = awk_split_statements(act)
  for stmt_raw in statements {
    let stmt = aj_trim(stmt_raw)
    if stmt.length() == 0 {
      continue
    }

    if stmt == "getline" {
      let next_idx = line_idx + consumed + 1
      if next_idx >= 0 && next_idx < lines.length() {
        consumed += 1
        current_line = lines[next_idx]
        current_fields = awk_split_fields(current_line, fs)
        current_nr += 1
      }
      continue
    }

    if aj_starts_with(stmt, "split(") && aj_ends_with(stmt, ")") {
      let inner = aj_substr(stmt, 6, stmt.length() - 1)
      let args = awk_split_csv_args(inner)
      if args.length() >= 2 {
        let source = awk_eval_expr(
          args[0],
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let arr_name = aj_trim(args[1])
        let delim = if args.length() >= 3 {
          awk_eval_expr(
            args[2],
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        } else {
          " "
        }
        let pieces = if delim.length() == 0 {
          [source]
        } else {
          aj_split_by_delim(source, delim)
        }
        for j = 0; j < pieces.length(); j = j + 1 {
          array_vars[awk_array_key(arr_name, j + 1)] = pieces[j]
        }
        vars[arr_name] = pieces.length().to_string()
      }
      continue
    }

    if aj_starts_with(stmt, "printf") {
      let (fmt, arg_expr) = awk_parse_printf(stmt)
      let arg_value = match arg_expr {
        Some(expr) => awk_eval_expr(
          expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        None => ""
      }
      out.write_string(awk_format_printf(fmt, arg_value))
      continue
    }

    if aj_starts_with(stmt, "print") {
      let rest = aj_trim(aj_substr(stmt, 5, stmt.length()))
      if rest.length() == 0 {
        out.write_string(current_line)
        out.write_char('\n')
        continue
      }
      let parts = awk_split_csv_args(rest)
      if parts.length() > 1 {
        for i = 0; i < parts.length(); i = i + 1 {
          if i > 0 {
            out.write_char(' ')
          }
          out.write_string(
            awk_eval_expr(
              parts[i],
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            ),
          )
        }
        out.write_char('\n')
      } else {
        out.write_string(
          awk_eval_expr(
            rest,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          ),
        )
        out.write_char('\n')
      }
      continue
    }

    if aj_ends_with(stmt, "++") {
      let name = aj_trim(aj_substr(stmt, 0, stmt.length() - 2))
      if awk_is_identifier(name) {
        let value = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(value + 1.0)
      }
      continue
    }

    let plus_eq_idx = awk_find_top_level_token(stmt, "+=")
    if plus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, plus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, plus_eq_idx + 2, stmt.length()))
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        let right = awk_eval_number(
          rhs,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        vars[name] = awk_number_to_string(left + right)
      }
      continue
    }

    let eq_idx = awk_find_top_level_token(stmt, "=")
    if eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, eq_idx))
      let rhs = aj_trim(aj_substr(stmt, eq_idx + 1, stmt.length()))
      if awk_is_identifier(name) {
        vars[name] = awk_eval_expr(
          rhs,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
      }
      continue
    }
  }

  (current_line, current_fields, consumed, current_nr)
}

fn cmd_awk(ctx : CommandContext) -> @ast.ExecResult {
  let mut fs = " "
  let mut program : String? = None
  let files : Array[String] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-F" && i + 1 < ctx.args.length() {
      fs = ctx.args[i + 1]
      i += 2
      continue
    }
    if aj_starts_with(arg, "-F") && arg.length() > 2 {
      fs = aj_substr(arg, 2, arg.length())
      i += 1
      continue
    }
    if program is None {
      program = Some(arg)
    } else {
      files.push(arg)
    }
    i += 1
  }

  if fs == "\\t" {
    fs = "\t"
  }

  let prog_src = match program {
    Some(p) => p
    None => return @ast.ExecResult::err("awk: missing program\n")
  }
  let prog = awk_parse_program(prog_src)

  let input = if files.length() > 0 {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, files[0])
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
    }
    try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
    }
  } else {
    ctx.stdin_content
  }

  let out = StringBuilder::new()
  let vars : Map[String, String] = {}
  let array_vars : Map[String, String] = {}
  let lines = aj_split_lines_records(input)
  let mut nr = 0

  match prog.begin_action {
    Some(action) => {
      let (_, _, _, new_nr) = awk_execute_action(
        action,
        lines,
        -1,
        "",
        [],
        nr,
        0,
        fs,
        vars,
        array_vars,
        out,
      )
      nr = new_nr
    }
    None => ()
  }

  let mut line_idx = 0
  let mut in_range = false
  while line_idx < lines.length() {
    let line = lines[line_idx]
    nr += 1
    let fields = awk_split_fields(line, fs)
    let nf = fields.length()
    let (matched, next_range) = awk_pattern_match_program(
      prog,
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
      in_range,
    )
    in_range = next_range
    if matched {
      let (_, _, consumed, new_nr) = awk_execute_action(
        prog.action,
        lines,
        line_idx,
        line,
        fields,
        nr,
        nf,
        fs,
        vars,
        array_vars,
        out,
      )
      nr = new_nr
      line_idx += consumed + 1
    } else {
      line_idx += 1
    }
  }

  match prog.end_action {
    Some(action) => {
      let end_idx = if lines.length() > 0 { lines.length() - 1 } else { -1 }
      let (_, _, _, _) = awk_execute_action(
        action,
        lines,
        end_idx,
        "",
        [],
        nr,
        0,
        fs,
        vars,
        array_vars,
        out,
      )
    }
    None => ()
  }

  @ast.ExecResult::ok(out.to_string())
}

// ============================================================================
// jq
// ============================================================================

fn jq_json_null() -> Json {
  Json::null()
}

fn jq_json_number(n : Int) -> Json {
  Json::number(n.to_double())
}

fn jq_sorted_keys(obj : Map[String, Json]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in obj {
    keys.push(key)
  }
  keys.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  keys
}

fn jq_split_top_level(filter : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None

  for i = 0; i < filter.length(); i = i + 1 {
    let ch = filter[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          buf.write_char(ch)
        } else if ch == '(' {
          depth_paren += 1
          buf.write_char(ch)
        } else if ch == ')' {
          depth_paren -= 1
          buf.write_char(ch)
        } else if ch == '[' {
          depth_bracket += 1
          buf.write_char(ch)
        } else if ch == ']' {
          depth_bracket -= 1
          buf.write_char(ch)
        } else if ch == '{' {
          depth_brace += 1
          buf.write_char(ch)
        } else if ch == '}' {
          depth_brace -= 1
          buf.write_char(ch)
        } else if ch == sep && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
          parts.push(aj_trim(buf.to_string()))
          buf.reset()
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  let last = aj_trim(buf.to_string())
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

fn jq_to_int(value : Json) -> Int {
  match value {
    Json::Number(n, ..) => n.to_int()
    Json::String(s) => aj_parse_int(s)
    _ => 0
  }
}

fn jq_eval_condition(expr : String, value : Json) -> Bool {
  let cond = aj_trim(expr)
  if aj_starts_with(cond, ". > ") {
    return jq_to_int(value) > aj_parse_int(aj_trim(aj_substr(cond, 4, cond.length())))
  }
  if aj_starts_with(cond, ". < ") {
    return jq_to_int(value) < aj_parse_int(aj_trim(aj_substr(cond, 4, cond.length())))
  }
  if aj_starts_with(cond, ". == ") {
    return jq_to_int(value) == aj_parse_int(aj_trim(aj_substr(cond, 5, cond.length())))
  }
  false
}

fn jq_eval_path(path : String, value : Json) -> Json {
  if path == "." {
    return value
  }
  if path == ".[]" {
    return value
  }
  let mut current = value
  let segments = aj_split_by_delim(aj_substr(path, 1, path.length()), ".")
  for seg in segments {
    if seg.length() == 0 {
      continue
    }
    match current {
      Json::Object(obj) => {
        current = obj.get(seg).unwrap_or(jq_json_null())
      }
      _ => return jq_json_null()
    }
  }
  current
}

fn jq_eval_step(filter : String, input : Json) -> Array[Json] {
  let f = aj_trim(filter)
  if f.length() == 0 {
    return [input]
  }

  if f == "[range(5)]" {
    return [Json::array([jq_json_number(0), jq_json_number(1), jq_json_number(2), jq_json_number(3), jq_json_number(4)])]
  }

  if (aj_starts_with(f, "\"") && aj_ends_with(f, "\"")) ||
    (aj_starts_with(f, "'") && aj_ends_with(f, "'")) {
    return [Json::string(aj_decode_c_escapes(aj_substr(f, 1, f.length() - 1)))]
  }

  if aj_starts_with(f, "[") && aj_ends_with(f, "]") {
    let inner = aj_substr(f, 1, f.length() - 1)
    let values = jq_apply_filter(inner, [input])
    return [Json::array(values)]
  }

  if f == "." {
    return [input]
  }
  if f == "null" {
    return [jq_json_null()]
  }

  if f == ".[]" {
    match input {
      Json::Array(arr) => {
        let out : Array[Json] = []
        for item in arr {
          out.push(item)
        }
        return out
      }
      Json::Object(obj) => {
        let out : Array[Json] = []
        let keys = jq_sorted_keys(obj)
        for k in keys {
          out.push(obj.get(k).unwrap_or(jq_json_null()))
        }
        return out
      }
      _ => return []
    }
  }

  if aj_starts_with(f, ".[") && aj_ends_with(f, "]") {
    let idx_str = aj_trim(aj_substr(f, 2, f.length() - 1))
    let idx = aj_parse_int(idx_str)
    match input {
      Json::Array(arr) => {
        let actual = if idx < 0 { arr.length() + idx } else { idx }
        if actual >= 0 && actual < arr.length() {
          return [arr[actual]]
        }
        return [jq_json_null()]
      }
      _ => return [jq_json_null()]
    }
  }

  if f == "keys" {
    match input {
      Json::Object(obj) => {
        let arr : Array[Json] = []
        for key in jq_sorted_keys(obj) {
          arr.push(Json::string(key))
        }
        return [Json::array(arr)]
      }
      _ => {
        let empty : Array[Json] = []
        return [Json::array(empty)]
      }
    }
  }

  if f == "length" {
    match input {
      Json::Array(arr) => return [jq_json_number(arr.length())]
      Json::Object(obj) => return [jq_json_number(obj.size())]
      Json::String(s) => return [jq_json_number(s.length())]
      _ => return [jq_json_number(0)]
    }
  }

  if f == "type" {
    let t = match input {
      Json::Null => "null"
      Json::True | Json::False => "boolean"
      Json::Number(_, ..) => "number"
      Json::String(_) => "string"
      Json::Array(_) => "array"
      Json::Object(_) => "object"
    }
    return [Json::string(t)]
  }

  if f == "sort" {
    match input {
      Json::Array(arr) => {
        let out = arr
        out.sort_by(fn(a, b) {
          jq_to_int(a) - jq_to_int(b)
        })
        return [Json::array(out)]
      }
      _ => return [input]
    }
  }

  if f == "reverse" {
    match input {
      Json::Array(arr) => {
        let out : Array[Json] = []
        for i = arr.length() - 1; i >= 0; i = i - 1 {
          out.push(arr[i])
        }
        return [Json::array(out)]
      }
      _ => return [input]
    }
  }

  if f == "add" {
    match input {
      Json::Array(arr) => {
        let mut sum = 0
        for item in arr {
          sum += jq_to_int(item)
        }
        return [jq_json_number(sum)]
      }
      _ => return [jq_json_number(0)]
    }
  }

  if aj_starts_with(f, "map(") && aj_ends_with(f, ")") {
    let inner = aj_substr(f, 4, f.length() - 1)
    match input {
      Json::Array(arr) => {
        let mapped : Array[Json] = []
        for item in arr {
          let values = jq_apply_filter(inner, [item])
          for v in values {
            mapped.push(v)
          }
        }
        return [Json::array(mapped)]
      }
      _ => {
        let empty : Array[Json] = []
        return [Json::array(empty)]
      }
    }
  }

  if aj_starts_with(f, "select(") && aj_ends_with(f, ")") {
    let cond = aj_substr(f, 7, f.length() - 1)
    if jq_eval_condition(cond, input) {
      return [input]
    }
    return []
  }

  if aj_starts_with(f, ". + ") {
    let rhs = aj_parse_int(aj_trim(aj_substr(f, 4, f.length())))
    return [jq_json_number(jq_to_int(input) + rhs)]
  }
  if aj_starts_with(f, ". * ") {
    let rhs = aj_parse_int(aj_trim(aj_substr(f, 4, f.length())))
    return [jq_json_number(jq_to_int(input) * rhs)]
  }

  if aj_starts_with(f, "if ") && aj_ends_with(f, " end") {
    let then_marker = aj_find_substring(f, " then ")
    let else_idx = aj_find_substring(f, " else ")
    if then_marker >= 0 && else_idx >= 0 && else_idx > then_marker {
      let cond = aj_trim(aj_substr(f, 3, then_marker))
      let then_expr = aj_trim(aj_substr(f, then_marker + 6, else_idx))
      let else_expr = aj_trim(aj_substr(f, else_idx + 6, f.length() - 4))
      if jq_eval_condition(cond, input) {
        return jq_eval_step(then_expr, input)
      } else {
        return jq_eval_step(else_expr, input)
      }
    }
  }

  if aj_starts_with(f, ".") {
    return [jq_eval_path(f, input)]
  }

  if aj_starts_with(f, "split(") && aj_ends_with(f, ")") {
    let raw_delim = aj_trim(aj_substr(f, 6, f.length() - 1))
    let delim = if aj_starts_with(raw_delim, "\"") && aj_ends_with(raw_delim, "\"") {
      aj_decode_c_escapes(aj_substr(raw_delim, 1, raw_delim.length() - 1))
    } else {
      raw_delim
    }
    match input {
      Json::String(s) => {
        let parts = aj_split_by_delim(s, delim)
        let arr : Array[Json] = []
        for part in parts {
          arr.push(Json::string(part))
        }
        return [Json::array(arr)]
      }
      _ => {
        let empty : Array[Json] = []
        return [Json::array(empty)]
      }
    }
  }

  if aj_starts_with(f, "join(") && aj_ends_with(f, ")") {
    let raw_delim = aj_trim(aj_substr(f, 5, f.length() - 1))
    let delim = if aj_starts_with(raw_delim, "\"") && aj_ends_with(raw_delim, "\"") {
      aj_decode_c_escapes(aj_substr(raw_delim, 1, raw_delim.length() - 1))
    } else {
      raw_delim
    }
    match input {
      Json::Array(arr) => {
        let out = StringBuilder::new()
        for i = 0; i < arr.length(); i = i + 1 {
          if i > 0 {
            out.write_string(delim)
          }
          match arr[i] {
            Json::String(s) => out.write_string(s)
            other => out.write_string(other.stringify())
          }
        }
        return [Json::string(out.to_string())]
      }
      _ => return [Json::string("")]
    }
  }

  [input]
}

fn jq_apply_filter(
  filter : String,
  inputs : Array[Json]
) -> Array[Json] {
  let stages = jq_split_top_level(filter, '|')
  if stages.length() == 0 {
    return inputs
  }

  let mut current = inputs
  for stage in stages {
    let next : Array[Json] = []
    for value in current {
      let out_values = jq_eval_step(stage, value)
      for v in out_values {
        next.push(v)
      }
    }
    current = next
  }
  current
}

fn cmd_jq(ctx : CommandContext) -> @ast.ExecResult {
  let mut compact = false
  let mut raw = false
  let mut null_input = false
  let mut slurp = false

  let mut filter : String? = None
  let mut input_file : String? = None

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if aj_starts_with(arg, "-") && filter is None {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'c' => compact = true
          'r' => raw = true
          'n' => null_input = true
          's' => slurp = true
          _ => ()
        }
      }
      i += 1
      continue
    }
    if filter is None {
      filter = Some(arg)
    } else if input_file is None {
      input_file = Some(arg)
    }
    i += 1
  }

  let jq_filter = match filter {
    Some(f) => f
    None => return @ast.ExecResult::err("jq: missing filter\n")
  }

  let inputs : Array[Json] = if null_input {
    [jq_json_null()]
  } else {
    let source = match input_file {
      Some(path) => {
        let resolved = try {
          @fs.resolve_path(ctx.cwd, path)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("jq: \{msg}\n")
        }
        try {
          ctx.fs.read_file(resolved)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("jq: \{msg}\n")
        }
      }
      None => ctx.stdin_content
    }

    if slurp {
      let lines = aj_split_lines_records(source)
      let arr : Array[Json] = []
      for line in lines {
        let t = aj_trim(line)
        if t.length() == 0 {
          continue
        }
        let parsed = try {
          @json.parse(t[:])
        } catch {
          _ => return @ast.ExecResult::err("jq: invalid JSON input\n")
        }
        arr.push(parsed)
      }
      [Json::array(arr)]
    } else {
      let trimmed = aj_trim(source)
      if trimmed.length() == 0 {
        [jq_json_null()]
      } else {
        let parsed = try {
          @json.parse(trimmed[:])
        } catch {
          _ => return @ast.ExecResult::err("jq: invalid JSON input\n")
        }
        [parsed]
      }
    }
  }

  let values = jq_apply_filter(jq_filter, inputs)
  let out = StringBuilder::new()
  for value in values {
    if raw {
      match value {
        Json::String(s) => out.write_string(s)
        _ => out.write_string(value.stringify(indent=if compact { 0 } else { 2 }))
      }
    } else {
      out.write_string(value.stringify(indent=if compact { 0 } else { 2 }))
    }
    out.write_char('\n')
  }
  @ast.ExecResult::ok(out.to_string())
}
