// moon_bash Commands - awk / jq (comparison-focused subset)

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

let awk_ctrl_next_key = "__moon_bash_awk_ctrl_next"
let awk_ctrl_exit_key = "__moon_bash_awk_ctrl_exit"
let awk_ctrl_error_key = "__moon_bash_awk_ctrl_error"

fn awk_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn awk_current_fs(default_fs : String, vars : Map[String, String]) -> String {
  vars.get("FS").unwrap_or(default_fs)
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

fn awk_normalize_array_index(index : String) -> String {
  let trimmed = aj_trim(index)
  if trimmed.length() == 0 {
    return ""
  }
  if awk_is_numeric_string(trimmed) {
    return awk_number_to_string(awk_parse_number(trimmed))
  }
  trimmed
}

fn awk_array_key(name : String, index : String) -> String {
  name + "#" + awk_normalize_array_index(index)
}

fn awk_parse_array_ref(expr : String) -> (String, String)? {
  let t = aj_trim(expr)
  if t.length() < 3 {
    return None
  }
  let open_bracket = aj_index_of(t, '[')
  if open_bracket <= 0 || t[t.length() - 1].to_int().unsafe_to_char() != ']' {
    return None
  }
  let arr_name = aj_trim(aj_substr(t, 0, open_bracket))
  if not(awk_is_identifier(arr_name)) {
    return None
  }
  let idx_expr = aj_trim(aj_substr(t, open_bracket + 1, t.length() - 1))
  if idx_expr.length() == 0 {
    return None
  }
  Some((arr_name, idx_expr))
}

fn awk_join_fields(fields : Array[String], sep : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < fields.length(); i = i + 1 {
    if i > 0 {
      out.write_string(sep)
    }
    out.write_string(fields[i])
  }
  out.to_string()
}

fn awk_split_chars(input : String) -> Array[String] {
  let parts : Array[String] = []
  for i = 0; i < input.length(); i = i + 1 {
    parts.push(aj_substr(input, i, i + 1))
  }
  parts
}

fn awk_split_for_split_builtin(source : String, delim : String) -> Array[String] {
  if delim.length() == 0 {
    return awk_split_chars(source)
  }
  if delim == " " {
    return awk_split_fields(source, " ")
  }
  aj_split_by_delim(source, delim)
}

fn awk_eval_split_delim(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let text = aj_trim(expr)
  if aj_starts_with(text, "/") && aj_ends_with(text, "/") && text.length() >= 2 {
    return aj_substr(text, 1, text.length() - 1)
  }
  awk_eval_expr(text, line, fields, nr, nf, vars, array_vars)
}

fn awk_is_wrapped_in_parens(expr : String) -> Bool {
  if expr.length() < 2 ||
    expr[0].to_int().unsafe_to_char() != '(' ||
    expr[expr.length() - 1].to_int().unsafe_to_char() != ')' {
    return false
  }
  let mut depth = 0
  let mut quote : Char? = None
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
        } else if ch == '(' {
          depth += 1
        } else if ch == ')' {
          depth -= 1
          if depth == 0 && i < expr.length() - 1 {
            return false
          }
        }
      }
    }
  }
  depth == 0
}

fn awk_strip_outer_parens(expr : String) -> String {
  let mut current = aj_trim(expr)
  while awk_is_wrapped_in_parens(current) {
    current = aj_trim(aj_substr(current, 1, current.length() - 1))
  }
  current
}

fn awk_find_top_level_ternary_colon(expr : String, start_idx : Int) -> Int {
  let mut quote : Char? = None
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut ternary_depth = 0
  for i = start_idx; i < expr.length(); i = i + 1 {
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
        } else if ch == '(' {
          paren_depth += 1
        } else if ch == ')' && paren_depth > 0 {
          paren_depth -= 1
        } else if ch == '[' {
          bracket_depth += 1
        } else if ch == ']' && bracket_depth > 0 {
          bracket_depth -= 1
        } else if paren_depth == 0 && bracket_depth == 0 {
          if ch == '?' {
            ternary_depth += 1
          } else if ch == ':' {
            if ternary_depth == 0 {
              return i
            }
            ternary_depth -= 1
          }
        }
      }
    }
  }
  -1
}

fn awk_replace_first_literal(
  source : String,
  pattern : String,
  replacement : String
) -> (String, Int) {
  if pattern.length() == 0 {
    return (source, 0)
  }
  let idx = aj_find_substring(source, pattern)
  if idx < 0 {
    return (source, 0)
  }
  let updated = aj_substr(source, 0, idx) +
    replacement +
    aj_substr(source, idx + pattern.length(), source.length())
  (updated, 1)
}

fn awk_replace_all_literal(
  source : String,
  pattern : String,
  replacement : String
) -> (String, Int) {
  if pattern.length() == 0 {
    return (source, 0)
  }
  let out = StringBuilder::new()
  let mut cursor = 0
  let mut count = 0
  while cursor <= source.length() {
    let rest = aj_substr(source, cursor, source.length())
    let rel_idx = aj_find_substring(rest, pattern)
    if rel_idx < 0 {
      out.write_string(rest)
      break
    }
    out.write_string(aj_substr(rest, 0, rel_idx))
    out.write_string(replacement)
    cursor += rel_idx + pattern.length()
    count += 1
  }
  (out.to_string(), count)
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
    return vars.get("NR").unwrap_or(nr.to_string())
  }
  if t == "NF" {
    return vars.get("NF").unwrap_or(nf.to_string())
  }
  if t == "FNR" {
    return vars.get("FNR").unwrap_or(nr.to_string())
  }
  if t == "FILENAME" {
    return vars.get("FILENAME").unwrap_or("")
  }
  if t == "RSTART" {
    return vars.get("RSTART").unwrap_or("0")
  }
  if t == "RLENGTH" {
    return vars.get("RLENGTH").unwrap_or("-1")
  }
  if t == "FS" {
    return vars.get("FS").unwrap_or("")
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

  match awk_parse_array_ref(t) {
    Some((arr_name, idx_expr)) => {
      let idx = awk_eval_expr(
        idx_expr,
        line,
        fields,
        nr,
        nf,
        vars,
        array_vars,
      )
      return array_vars.get(awk_array_key(arr_name, idx)).unwrap_or("")
    }
    None => ()
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
  let mut paren_depth = 0
  let mut bracket_depth = 0
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
        } else if ch == '(' {
          paren_depth += 1
          buf.write_char(ch)
        } else if ch == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == '[' {
          bracket_depth += 1
          buf.write_char(ch)
        } else if ch == ']' {
          if bracket_depth > 0 {
            bracket_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == ' ' || ch == '\t' {
          if paren_depth == 0 && bracket_depth == 0 {
            let tok = buf.to_string()
            if tok.length() > 0 {
              tokens.push(tok)
              buf.reset()
            }
          } else {
            buf.write_char(ch)
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

  if aj_starts_with(t, "sprintf(") && aj_ends_with(t, ")") {
    let inner = aj_substr(t, 8, t.length() - 1)
    let args = awk_split_csv_args(inner)
    if args.length() == 0 {
      return ""
    }
    let format = awk_eval_expr(
      args[0],
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let format_args : Array[String] = []
    for i = 1; i < args.length(); i = i + 1 {
      format_args.push(
        awk_eval_expr(
          args[i],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        ),
      )
    }
    return awk_format_printf(format, format_args)
  }

  if aj_starts_with(t, "split(") && aj_ends_with(t, ")") {
    let inner = aj_substr(t, 6, t.length() - 1)
    let args = awk_split_csv_args(inner)
    if args.length() >= 2 {
      let source = awk_eval_expr(
        args[0],
        line,
        fields,
        nr,
        nf,
        vars,
        array_vars,
      )
      let arr_name = aj_trim(args[1])
      let delim = if args.length() >= 3 {
        awk_eval_split_delim(
          args[2],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
      } else {
        awk_current_fs(vars.get("FS").unwrap_or(" "), vars)
      }
      let pieces = awk_split_for_split_builtin(source, delim)
      for i = 0; i < pieces.length(); i = i + 1 {
        array_vars[awk_array_key(arr_name, (i + 1).to_string())] = pieces[i]
      }
      vars[arr_name] = pieces.length().to_string()
      return pieces.length().to_string()
    }
    return "0"
  }

  let question_idx = awk_find_top_level_token(t, "?")
  if question_idx > 0 {
    let colon_idx = awk_find_top_level_ternary_colon(t, question_idx + 1)
    if colon_idx > question_idx {
      let cond_expr = aj_substr(t, 0, question_idx)
      let true_expr = aj_substr(t, question_idx + 1, colon_idx)
      let false_expr = aj_substr(t, colon_idx + 1, t.length())
      if awk_eval_condition(cond_expr, line, fields, nr, nf, vars, array_vars) {
        return awk_eval_expr(true_expr, line, fields, nr, nf, vars, array_vars)
      } else {
        return awk_eval_expr(false_expr, line, fields, nr, nf, vars, array_vars)
      }
    }
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

  if tokens.length() > 1 {
    let out = StringBuilder::new()
    for tok in tokens {
      out.write_string(awk_eval_expr(tok, line, fields, nr, nf, vars, array_vars))
    }
    return out.to_string()
  }

  awk_eval_atom(t, line, fields, nr, nf, vars, array_vars)
}

fn awk_split_csv_args(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  let mut paren_depth = 0
  let mut bracket_depth = 0
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
        } else if ch == '(' {
          paren_depth += 1
          buf.write_char(ch)
        } else if ch == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == '[' {
          bracket_depth += 1
          buf.write_char(ch)
        } else if ch == ']' {
          if bracket_depth > 0 {
            bracket_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == ',' && paren_depth == 0 && bracket_depth == 0 {
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

fn awk_parse_printf(action : String) -> (String, Array[String]) {
  let rest = aj_trim(aj_substr(action, 6, action.length()))
  if rest.length() == 0 {
    return ("", [])
  }
  let args = awk_split_csv_args(rest)
  if args.length() == 0 {
    return ("", [])
  }
  let tail : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    tail.push(args[i])
  }
  (args[0], tail)
}

fn awk_format_printf(format : String, args : Array[String]) -> String {
  let decoded = aj_decode_c_escapes(format)
  let out = StringBuilder::new()
  let mut arg_idx = 0
  let mut i = 0
  while i < decoded.length() {
    let ch = decoded[i].to_int().unsafe_to_char()
    if ch == '%' {
      if i + 1 < decoded.length() && decoded[i + 1].to_int().unsafe_to_char() == '%' {
        out.write_char('%')
        i += 2
        continue
      }
      let mut j = i + 1
      let mut width = 0
      let mut has_width = false
      while j < decoded.length() {
        let wch = decoded[j].to_int().unsafe_to_char()
        if wch >= '0' && wch <= '9' {
          has_width = true
          width = width * 10 + (wch.to_int() - '0'.to_int())
          j += 1
        } else {
          break
        }
      }
      if width > 10000 {
        width = 10000
      }
      if j >= decoded.length() {
        out.write_char('%')
        i += 1
        continue
      }
      let spec = decoded[j].to_int().unsafe_to_char()
      if spec == 's' {
        let value = if arg_idx < args.length() { args[arg_idx] } else { "" }
        arg_idx += 1
        if has_width {
          let mut pad = width - value.length()
          while pad > 0 {
            out.write_char(' ')
            pad -= 1
          }
        }
        out.write_string(value)
        i = j + 1
        continue
      }
      if spec == 'd' {
        let raw = if arg_idx < args.length() { args[arg_idx] } else { "0" }
        arg_idx += 1
        let value = aj_parse_int(raw).to_string()
        if has_width {
          let mut pad = width - value.length()
          while pad > 0 {
            out.write_char(' ')
            pad -= 1
          }
        }
        out.write_string(value)
        i = j + 1
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn awk_find_regex_match_range(pattern_expr : String, input : String) -> (Int, Int) {
  let mut pat = aj_trim(pattern_expr)
  if aj_starts_with(pat, "/") && aj_ends_with(pat, "/") && pat.length() >= 2 {
    pat = aj_substr(pat, 1, pat.length() - 1)
  }
  if pat.length() == 0 {
    return (1, 0)
  }
  if aj_starts_with(pat, "^") && aj_ends_with(pat, "$") {
    let inner = aj_substr(pat, 1, pat.length() - 1)
    if input == inner {
      return (1, inner.length())
    }
    return (0, -1)
  }
  if aj_starts_with(pat, "^") {
    let prefix = aj_substr(pat, 1, pat.length())
    if aj_starts_with(input, prefix) {
      return (1, prefix.length())
    }
    return (0, -1)
  }
  if aj_ends_with(pat, "$") {
    let suffix = aj_substr(pat, 0, pat.length() - 1)
    if aj_ends_with(input, suffix) {
      return (input.length() - suffix.length() + 1, suffix.length())
    }
    return (0, -1)
  }
  let idx = aj_find_substring(input, pat)
  if idx >= 0 {
    (idx + 1, pat.length())
  } else {
    (0, -1)
  }
}

fn awk_parse_if_statement(stmt : String) -> (String, String)? {
  let text = aj_trim(stmt)
  if not(aj_starts_with(text, "if")) {
    return None
  }
  if text.length() > 2 {
    let boundary = text[2].to_int().unsafe_to_char()
    if not(awk_is_space(boundary)) && boundary != '(' {
      return None
    }
  }

  let mut i = 2
  while i < text.length() && awk_is_space(text[i].to_int().unsafe_to_char()) {
    i += 1
  }
  if i >= text.length() || text[i].to_int().unsafe_to_char() != '(' {
    return None
  }

  let mut depth = 1
  let mut j = i + 1
  let mut quote : Char? = None
  while j < text.length() {
    let ch = text[j].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && j + 1 < text.length() {
          j += 2
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
        } else if ch == '(' {
          depth += 1
        } else if ch == ')' {
          depth -= 1
          if depth == 0 {
            break
          }
        }
      }
    }
    j += 1
  }
  if j >= text.length() || depth != 0 {
    return None
  }

  let cond = aj_trim(aj_substr(text, i + 1, j))
  let mut body = aj_trim(aj_substr(text, j + 1, text.length()))
  if body.length() == 0 {
    return None
  }
  if body.length() >= 2 &&
    body[0].to_int().unsafe_to_char() == '{' &&
    body[body.length() - 1].to_int().unsafe_to_char() == '}' {
    body = aj_trim(aj_substr(body, 1, body.length() - 1))
  }
  Some((cond, body))
}

fn awk_parse_print_redirection(expr : String) -> (String, String, Bool)? {
  let text = aj_trim(expr)
  let append_idx = awk_find_top_level_token(text, ">>")
  if append_idx >= 0 {
    let left = aj_trim(aj_substr(text, 0, append_idx))
    let right = aj_trim(aj_substr(text, append_idx + 2, text.length()))
    if right.length() > 0 {
      return Some((left, right, true))
    }
  }

  let idx = awk_find_top_level_token(text, ">")
  if idx >= 0 {
    let left = aj_trim(aj_substr(text, 0, idx))
    let right = aj_trim(aj_substr(text, idx + 1, text.length()))
    if right.length() > 0 {
      return Some((left, right, false))
    }
  }
  None
}

fn awk_render_print_output(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let rest = aj_trim(expr)
  if rest.length() == 0 {
    return line + "\n"
  }

  let parts = awk_split_csv_args(rest)
  let out = StringBuilder::new()
  if parts.length() > 1 {
    for i = 0; i < parts.length(); i = i + 1 {
      if i > 0 {
        out.write_char(' ')
      }
      out.write_string(
        awk_eval_expr(
          parts[i],
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
        ),
      )
    }
  } else {
    out.write_string(
      awk_eval_expr(
        rest,
        line,
        fields,
        nr,
        fields.length(),
        vars,
        array_vars,
      ),
    )
  }
  out.write_char('\n')
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
  let p = awk_strip_outer_parens(expr)
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

  let in_idx = awk_find_top_level_token(p, " in ")
  if in_idx > 0 {
    let left_expr = aj_substr(p, 0, in_idx)
    let right_expr = aj_trim(aj_substr(p, in_idx + 4, p.length()))
    if awk_is_identifier(right_expr) {
      let idx_value = awk_eval_expr(
        left_expr,
        line,
        fields,
        nr,
        nf,
        vars,
        array_vars,
      )
      return array_vars.contains(awk_array_key(right_expr, idx_value))
    }
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
  let mut paren_depth = 0
  let mut brace_depth = 0
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
        } else if ch == '(' {
          paren_depth += 1
          buf.write_char(ch)
        } else if ch == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == '{' {
          brace_depth += 1
          buf.write_char(ch)
        } else if ch == '}' {
          if brace_depth > 0 {
            brace_depth -= 1
          }
          buf.write_char(ch)
        } else if (ch == ';' || ch == '\n' || ch == '\r') &&
          paren_depth == 0 &&
          brace_depth == 0 {
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

let awk_loop_guard_limit : Int = 10_000

fn awk_split_for_header(header : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  let mut paren_depth = 0
  for i = 0; i < header.length(); i = i + 1 {
    let ch = header[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == '\\' && i + 1 < header.length() {
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
        } else if ch == '(' {
          paren_depth += 1
          buf.write_char(ch)
        } else if ch == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == ';' && paren_depth == 0 {
          parts.push(aj_trim(buf.to_string()))
          buf.reset()
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  parts.push(aj_trim(buf.to_string()))
  parts
}

fn awk_parse_for_statement(stmt : String) -> (String, String, String, String)? {
  let text = aj_trim(stmt)
  if not(aj_starts_with(text, "for")) {
    return None
  }
  let mut i = 3
  while i < text.length() && awk_is_space(text[i].to_int().unsafe_to_char()) {
    i += 1
  }
  if i >= text.length() || text[i].to_int().unsafe_to_char() != '(' {
    return None
  }

  let mut depth = 1
  let mut j = i + 1
  let mut quote : Char? = None
  while j < text.length() {
    let ch = text[j].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && j + 1 < text.length() {
          j += 2
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
        } else if ch == '(' {
          depth += 1
        } else if ch == ')' {
          depth -= 1
          if depth == 0 {
            break
          }
        }
      }
    }
    j += 1
  }
  if j >= text.length() || depth != 0 {
    return None
  }

  let header = aj_substr(text, i + 1, j)
  let mut body = aj_trim(aj_substr(text, j + 1, text.length()))
  if body.length() >= 2 &&
    body[0].to_int().unsafe_to_char() == '{' &&
    body[body.length() - 1].to_int().unsafe_to_char() == '}' {
    body = aj_trim(aj_substr(body, 1, body.length() - 1))
  }
  let parts = awk_split_for_header(header)
  if parts.length() != 3 {
    return None
  }
  Some((parts[0], parts[1], parts[2], body))
}

fn awk_parse_for_in_statement(stmt : String) -> (String, String, String)? {
  let text = aj_trim(stmt)
  if not(aj_starts_with(text, "for")) {
    return None
  }
  let mut i = 3
  while i < text.length() && awk_is_space(text[i].to_int().unsafe_to_char()) {
    i += 1
  }
  if i >= text.length() || text[i].to_int().unsafe_to_char() != '(' {
    return None
  }

  let mut depth = 1
  let mut j = i + 1
  let mut quote : Char? = None
  while j < text.length() {
    let ch = text[j].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && j + 1 < text.length() {
          j += 2
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
        } else if ch == '(' {
          depth += 1
        } else if ch == ')' {
          depth -= 1
          if depth == 0 {
            break
          }
        }
      }
    }
    j += 1
  }
  if j >= text.length() || depth != 0 {
    return None
  }

  let header = aj_trim(aj_substr(text, i + 1, j))
  if awk_find_top_level_token(header, ";") >= 0 {
    return None
  }
  let in_idx = awk_find_top_level_token(header, " in ")
  if in_idx <= 0 {
    return None
  }
  let var_name = aj_trim(aj_substr(header, 0, in_idx))
  let arr_name = aj_trim(aj_substr(header, in_idx + 4, header.length()))
  if not(awk_is_identifier(var_name)) || not(awk_is_identifier(arr_name)) {
    return None
  }

  let mut body = aj_trim(aj_substr(text, j + 1, text.length()))
  if body.length() >= 2 &&
    body[0].to_int().unsafe_to_char() == '{' &&
    body[body.length() - 1].to_int().unsafe_to_char() == '}' {
    body = aj_trim(aj_substr(body, 1, body.length() - 1))
  }
  Some((var_name, arr_name, body))
}

fn awk_parse_var_assignment(spec : String) -> (String, String)? {
  let eq_idx = aj_index_of(spec, '=')
  if eq_idx <= 0 {
    return None
  }
  let name = aj_trim(aj_substr(spec, 0, eq_idx))
  let value = aj_substr(spec, eq_idx + 1, spec.length())
  if not(awk_is_identifier(name)) {
    return None
  }
  Some((name, value))
}

fn awk_execute_action(
  ctx : CommandContext,
  action : String,
  lines : Array[String],
  line_idx : Int,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  fs : String,
  filename : String,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> (String, Array[String], Int, Int) {
  ignore(nf)
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
    if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_next_key) {
      break
    }
    let stmt = aj_trim(stmt_raw)
    if stmt.length() == 0 {
      continue
    }

    match awk_parse_for_in_statement(stmt) {
      Some((loop_var, arr_name, body_stmt)) => {
        let key_prefix = arr_name + "#"
        let indices : Array[String] = []
        for key, _value in array_vars {
          if aj_starts_with(key, key_prefix) {
            indices.push(aj_substr(key, key_prefix.length(), key.length()))
          }
        }
        for idx_value in indices {
          if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_next_key) {
            break
          }
          vars[loop_var] = idx_value
          if body_stmt.length() > 0 {
            let (next_line, next_fields, consumed_body, new_nr) = awk_execute_action(
              ctx,
              body_stmt,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
            current_line = next_line
            current_fields = next_fields
            consumed += consumed_body
            current_nr = new_nr
          }
        }
        continue
      }
      None => ()
    }

    match awk_parse_for_statement(stmt) {
      Some((init_stmt, cond_expr, update_stmt, body_stmt)) => {
        if init_stmt.length() > 0 {
          let (next_line, next_fields, consumed_init, new_nr) = awk_execute_action(
            ctx,
            init_stmt,
            lines,
            line_idx + consumed,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            fs,
            filename,
            vars,
            array_vars,
            out,
          )
          current_line = next_line
          current_fields = next_fields
          consumed += consumed_init
          current_nr = new_nr
        }

        let mut loop_count = 0
        while true {
          if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_next_key) {
            break
          }
          if cond_expr.length() > 0 &&
            not(
              awk_eval_condition(
                cond_expr,
                current_line,
                current_fields,
                current_nr,
                current_fields.length(),
                vars,
                array_vars,
              ),
            ) {
            break
          }

          if body_stmt.length() > 0 {
            let (next_line, next_fields, consumed_body, new_nr) = awk_execute_action(
              ctx,
              body_stmt,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
            current_line = next_line
            current_fields = next_fields
            consumed += consumed_body
            current_nr = new_nr
          }

          if update_stmt.length() > 0 {
            let (next_line, next_fields, consumed_update, new_nr) = awk_execute_action(
              ctx,
              update_stmt,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
            current_line = next_line
            current_fields = next_fields
            consumed += consumed_update
            current_nr = new_nr
          }

          loop_count += 1
          if loop_count > awk_loop_guard_limit {
            break
          }
        }
        continue
      }
      None => ()
    }

    match awk_parse_if_statement(stmt) {
      Some((cond_expr, body_stmt)) => {
        if awk_eval_condition(
          cond_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        ) {
          let (next_line, next_fields, consumed_if, new_nr) = awk_execute_action(
            ctx,
            body_stmt,
            lines,
            line_idx + consumed,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            fs,
            filename,
            vars,
            array_vars,
            out,
          )
          current_line = next_line
          current_fields = next_fields
          consumed += consumed_if
          current_nr = new_nr
        }
        continue
      }
      None => ()
    }

    if stmt == "next" {
      vars[awk_ctrl_next_key] = "1"
      break
    }

    if stmt == "exit" || aj_starts_with(stmt, "exit ") {
      let code_expr = if stmt.length() > 4 {
        aj_trim(aj_substr(stmt, 4, stmt.length()))
      } else {
        ""
      }
      let code = if code_expr.length() == 0 {
        0
      } else {
        awk_eval_number(
          code_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        ).to_int()
      }
      vars[awk_ctrl_exit_key] = code.to_string()
      break
    }

    if aj_starts_with(stmt, "system(") && aj_ends_with(stmt, ")") {
      vars[awk_ctrl_error_key] = "system() is not supported"
      vars[awk_ctrl_exit_key] = "1"
      break
    }

    if stmt == "getline" {
      let next_idx = line_idx + consumed + 1
      if next_idx >= 0 && next_idx < lines.length() {
        consumed += 1
        current_line = lines[next_idx]
        let current_fs = awk_current_fs(fs, vars)
        current_fields = awk_split_fields(current_line, current_fs)
        current_nr += 1
        vars["NR"] = current_nr.to_string()
        vars["FNR"] = current_nr.to_string()
        vars["NF"] = current_fields.length().to_string()
        vars["FILENAME"] = filename
      }
      continue
    }

    if aj_starts_with(stmt, "delete ") {
      let target = aj_trim(aj_substr(stmt, 6, stmt.length()))
      match awk_parse_array_ref(target) {
        Some((arr_name, idx_expr)) => {
          let idx = awk_eval_expr(
            idx_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          array_vars.remove(awk_array_key(arr_name, idx))
        }
        None => ()
      }
      continue
    }

    let is_gsub = aj_starts_with(stmt, "gsub(") && aj_ends_with(stmt, ")")
    let is_sub = aj_starts_with(stmt, "sub(") && aj_ends_with(stmt, ")")
    if is_gsub || is_sub {
      let offset = if is_gsub { 5 } else { 4 }
      let inner = aj_substr(stmt, offset, stmt.length() - 1)
      let args = awk_split_csv_args(inner)
      if args.length() >= 2 {
        let pattern = awk_eval_split_delim(
          args[0],
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let replacement = awk_eval_expr(
          args[1],
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let mut target_expr : String? = None
        if args.length() >= 3 {
          target_expr = Some(aj_trim(args[2]))
        }
        let source = match target_expr {
          Some(expr) => awk_eval_expr(
            expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          None => current_line
        }
        let (updated, _count) = if is_gsub {
          awk_replace_all_literal(source, pattern, replacement)
        } else {
          awk_replace_first_literal(source, pattern, replacement)
        }
        match target_expr {
          Some(expr) => {
            if awk_is_identifier(expr) {
              vars[expr] = updated
            } else {
              match awk_parse_array_ref(expr) {
                Some((arr_name, idx_expr)) => {
                  let idx = awk_eval_expr(
                    idx_expr,
                    current_line,
                    current_fields,
                    current_nr,
                    current_fields.length(),
                    vars,
                    array_vars,
                  )
                  array_vars[awk_array_key(arr_name, idx)] = updated
                }
                None => ()
              }
            }
          }
          None => {
            current_line = updated
            let current_fs = awk_current_fs(fs, vars)
            current_fields = awk_split_fields(current_line, current_fs)
            vars["NF"] = current_fields.length().to_string()
          }
        }
      }
      continue
    }

    if aj_starts_with(stmt, "match(") && aj_ends_with(stmt, ")") {
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
        let pattern_expr = aj_trim(args[1])
        let pattern = if aj_starts_with(pattern_expr, "/") &&
          aj_ends_with(pattern_expr, "/") {
          pattern_expr
        } else {
          awk_eval_expr(
            pattern_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        }
        let (rstart, rlength) = awk_find_regex_match_range(pattern, source)
        vars["RSTART"] = rstart.to_string()
        vars["RLENGTH"] = rlength.to_string()
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
          awk_eval_split_delim(
            args[2],
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        } else {
          awk_current_fs(fs, vars)
        }
        let pieces = awk_split_for_split_builtin(source, delim)
        for j = 0; j < pieces.length(); j = j + 1 {
          array_vars[awk_array_key(arr_name, (j + 1).to_string())] = pieces[j]
        }
        vars[arr_name] = pieces.length().to_string()
      }
      continue
    }

    if aj_starts_with(stmt, "printf") {
      let (fmt_expr, arg_exprs) = awk_parse_printf(stmt)
      let fmt_value = awk_eval_expr(
        fmt_expr,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      let fmt_args : Array[String] = []
      for expr in arg_exprs {
        fmt_args.push(
          awk_eval_expr(
            expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          ),
        )
      }
      out.write_string(awk_format_printf(fmt_value, fmt_args))
      continue
    }

    if aj_starts_with(stmt, "print") {
      let rest = aj_trim(aj_substr(stmt, 5, stmt.length()))
      if awk_find_top_level_token(rest, "|") >= 0 {
        vars[awk_ctrl_error_key] = "piping to external commands is not supported"
        vars[awk_ctrl_exit_key] = "1"
        break
      }
      match awk_parse_print_redirection(rest) {
        Some((value_expr, target_expr, append)) => {
          let payload = awk_render_print_output(
            value_expr,
            current_line,
            current_fields,
            current_nr,
            vars,
            array_vars,
          )
          let target = awk_eval_expr(
            target_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          let resolved = try {
            @fs.resolve_path(ctx.cwd, target)
          } catch {
            @fs.FsError(msg) => {
              vars[awk_ctrl_error_key] = msg
              vars[awk_ctrl_exit_key] = "1"
              break
            }
          }
          let existing = if append {
            try {
              ctx.fs.read_file(resolved)
            } catch {
              @fs.FsError(_) => ""
            }
          } else {
            ""
          }
          try {
            ctx.fs.write_file(resolved, existing + payload)
          } catch {
            @fs.FsError(msg) => {
              vars[awk_ctrl_error_key] = msg
              vars[awk_ctrl_exit_key] = "1"
              break
            }
          }
        }
        None => {
          out.write_string(
            awk_render_print_output(
              rest,
              current_line,
              current_fields,
              current_nr,
              vars,
              array_vars,
            ),
          )
        }
      }
      continue
    }

    if aj_ends_with(stmt, "++") {
      let name = aj_trim(aj_substr(stmt, 0, stmt.length() - 2))
      if awk_is_identifier(name) {
        let value = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(value + 1.0)
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            let key = awk_array_key(arr_name, idx)
            let value = awk_parse_number(array_vars.get(key).unwrap_or(""))
            array_vars[key] = awk_number_to_string(value + 1.0)
          }
          None => ()
        }
      }
      continue
    }

    let plus_eq_idx = awk_find_top_level_token(stmt, "+=")
    if plus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, plus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, plus_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(left + right)
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            let key = awk_array_key(arr_name, idx)
            let left = awk_parse_number(array_vars.get(key).unwrap_or(""))
            array_vars[key] = awk_number_to_string(left + right)
          }
          None => ()
        }
      }
      continue
    }

    let minus_eq_idx = awk_find_top_level_token(stmt, "-=")
    if minus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, minus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, minus_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(left - right)
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            let key = awk_array_key(arr_name, idx)
            let left = awk_parse_number(array_vars.get(key).unwrap_or(""))
            array_vars[key] = awk_number_to_string(left - right)
          }
          None => ()
        }
      }
      continue
    }

    let mul_eq_idx = awk_find_top_level_token(stmt, "*=")
    if mul_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, mul_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, mul_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(left * right)
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            let key = awk_array_key(arr_name, idx)
            let left = awk_parse_number(array_vars.get(key).unwrap_or(""))
            array_vars[key] = awk_number_to_string(left * right)
          }
          None => ()
        }
      }
      continue
    }

    let div_eq_idx = awk_find_top_level_token(stmt, "/=")
    if div_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, div_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, div_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        let value = if right == 0.0 { 0.0 } else { left / right }
        vars[name] = awk_number_to_string(value)
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            let key = awk_array_key(arr_name, idx)
            let left = awk_parse_number(array_vars.get(key).unwrap_or(""))
            let value = if right == 0.0 { 0.0 } else { left / right }
            array_vars[key] = awk_number_to_string(value)
          }
          None => ()
        }
      }
      continue
    }

    let eq_idx = awk_find_top_level_token(stmt, "=")
    if eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, eq_idx))
      let rhs = aj_trim(aj_substr(stmt, eq_idx + 1, stmt.length()))
      let value = awk_eval_expr(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        vars[name] = value
        if name == "FS" {
          let current_fs = awk_current_fs(fs, vars)
          current_fields = awk_split_fields(current_line, current_fs)
          vars["NF"] = current_fields.length().to_string()
        }
      } else if name == "$0" {
        current_line = value
        let current_fs = awk_current_fs(fs, vars)
        current_fields = awk_split_fields(current_line, current_fs)
        vars["NF"] = current_fields.length().to_string()
      } else if aj_starts_with(name, "$") {
        let field_idx = aj_parse_int(aj_substr(name, 1, name.length()))
        if field_idx == 0 {
          current_line = value
          let current_fs = awk_current_fs(fs, vars)
          current_fields = awk_split_fields(current_line, current_fs)
          vars["NF"] = current_fields.length().to_string()
        } else if field_idx > 0 {
          while current_fields.length() < field_idx {
            current_fields.push("")
          }
          current_fields[field_idx - 1] = value
          let ofs = vars.get("OFS").unwrap_or(" ")
          current_line = awk_join_fields(current_fields, ofs)
          vars["NF"] = current_fields.length().to_string()
        }
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            array_vars[awk_array_key(arr_name, idx)] = value
          }
          None => ()
        }
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
  let initial_vars : Array[(String, String)] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-v" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("awk: option -v requires an argument\n")
      }
      match awk_parse_var_assignment(ctx.args[i + 1]) {
        Some((name, value)) => initial_vars.push((name, value))
        None => return @ast.ExecResult::err("awk: invalid -v assignment: \{ctx.args[i + 1]}\n")
      }
      i += 2
      continue
    }
    if aj_starts_with(arg, "-v") && arg.length() > 2 {
      let spec = aj_substr(arg, 2, arg.length())
      match awk_parse_var_assignment(spec) {
        Some((name, value)) => initial_vars.push((name, value))
        None => return @ast.ExecResult::err("awk: invalid -v assignment: \{spec}\n")
      }
      i += 1
      continue
    }
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

  let (input, filename) = if files.length() > 0 {
    let path = files[0]
    if path == "-" {
      (ctx.stdin_content, "-")
    } else if path == "/dev/null" {
      ("", "/dev/null")
    } else {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, path)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
      }
      let content = try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
      }
      (content, path)
    }
  } else {
    (ctx.stdin_content, "-")
  }

  let out = StringBuilder::new()
  let vars : Map[String, String] = {}
  let array_vars : Map[String, String] = {}
  let lines = aj_split_lines_records(input)
  let mut nr = 0
  vars["FS"] = fs
  vars["FILENAME"] = filename
  vars["NR"] = "0"
  vars["FNR"] = "0"
  vars["NF"] = "0"
  vars["RSTART"] = "0"
  vars["RLENGTH"] = "-1"
  for pair in initial_vars {
    vars[pair.0] = pair.1
  }

  match prog.begin_action {
    Some(action) => {
      let (_, _, _, new_nr) = awk_execute_action(
        ctx,
        action,
        lines,
        -1,
        "",
        [],
        nr,
        0,
        fs,
        filename,
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
    if vars.contains(awk_ctrl_exit_key) {
      break
    }
    let line = lines[line_idx]
    nr += 1
    vars["NR"] = nr.to_string()
    vars["FNR"] = nr.to_string()
    vars["FILENAME"] = filename
    let current_fs = awk_current_fs(fs, vars)
    let fields = awk_split_fields(line, current_fs)
    let nf = fields.length()
    vars["NF"] = nf.to_string()
    vars.remove(awk_ctrl_next_key)
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
        ctx,
        prog.action,
        lines,
        line_idx,
        line,
        fields,
        nr,
        nf,
        fs,
        filename,
        vars,
        array_vars,
        out,
      )
      nr = new_nr
      vars["NR"] = nr.to_string()
      vars["FNR"] = nr.to_string()
      vars.remove(awk_ctrl_next_key)
      line_idx += consumed + 1
    } else {
      line_idx += 1
    }
  }

  if not(vars.contains(awk_ctrl_error_key)) {
    match prog.end_action {
      Some(action) => {
        let end_idx = if lines.length() > 0 { lines.length() - 1 } else { -1 }
        let (_, _, _, _) = awk_execute_action(
          ctx,
          action,
          lines,
          end_idx,
          "",
          [],
          nr,
          0,
          fs,
          filename,
          vars,
          array_vars,
          out,
        )
      }
      None => ()
    }
  }

  let exit_code = match vars.get(awk_ctrl_exit_key) {
    Some(code) => aj_parse_int(code)
    None => 0
  }
  let stderr = match vars.get(awk_ctrl_error_key) {
    Some(msg) => "awk: \{msg}\n"
    None => ""
  }
  @ast.ExecResult::new(stdout=out.to_string(), stderr=stderr, exit_code=exit_code)
}

// ============================================================================
// jq
// ============================================================================

// jq execution is delegated to bobzhang/moonjq.
// Keep lightweight filter rewrites for compatibility with existing tests.

fn jq_is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

fn jq_is_ident_char(ch : Char) -> Bool {
  jq_is_ident_start(ch) || (ch >= '0' && ch <= '9')
}

fn jq_starts_with_at(s : String, pos : Int, needle : String) -> Bool {
  if pos < 0 || pos + needle.length() > s.length() {
    return false
  }
  for i = 0; i < needle.length(); i = i + 1 {
    if s[pos + i] != needle[i] {
      return false
    }
  }
  true
}

fn jq_is_ws(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn jq_prev_non_ws_char(s : String, pos : Int) -> Char? {
  let mut i = pos - 1
  while i >= 0 {
    let ch = s[i].to_int().unsafe_to_char()
    if not(jq_is_ws(ch)) {
      return Some(ch)
    }
    i -= 1
  }
  None
}

fn jq_next_non_ws_char(s : String, pos : Int) -> Char? {
  let mut i = pos
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if not(jq_is_ws(ch)) {
      return Some(ch)
    }
    i += 1
  }
  None
}

fn jq_rewrite_keys_builtin(filter : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let mut quote : Char? = None

  while i < filter.length() {
    let ch = filter[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        out.write_char(ch)
        if ch == '\\' && i + 1 < filter.length() {
          i += 1
          out.write_char(filter[i].to_int().unsafe_to_char())
        } else if ch == q {
          quote = None
        }
        i += 1
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          out.write_char(ch)
          i += 1
          continue
        }

        if jq_starts_with_at(filter, i, "keys") {
          let left_ok = if i == 0 {
            true
          } else {
            not(jq_is_ident_char(filter[i - 1].to_int().unsafe_to_char()))
          }
          let right_pos = i + 4
          let right_ok = if right_pos >= filter.length() {
            true
          } else {
            not(jq_is_ident_char(filter[right_pos].to_int().unsafe_to_char()))
          }
          if left_ok && right_ok {
            let prev_sig = jq_prev_non_ws_char(filter, i)
            let next_sig = jq_next_non_ws_char(filter, right_pos)

            let is_member_or_var = match prev_sig {
              Some(prev) => prev == '.' || prev == '$'
              None => false
            }
            let is_object_key = match next_sig {
              Some(next) => next == ':'
              None => false
            }
            let is_object_shorthand = match prev_sig {
              Some(prev) => if prev == '{' || prev == ',' {
                match next_sig {
                  Some(next) => next == '}' || next == ','
                  None => false
                }
              } else {
                false
              }
              None => false
            }

            if not(is_member_or_var) &&
              not(is_object_key) &&
              not(is_object_shorthand) {
              out.write_string("(keys|sort)")
              i += 4
              continue
            }
          }
        }

        out.write_char(ch)
        i += 1
      }
    }
  }
  out.to_string()
}

fn jq_normalize_def_param_dollars(filter : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let mut quote : Char? = None

  while i < filter.length() {
    let ch = filter[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        out.write_char(ch)
        if ch == '\\' && i + 1 < filter.length() {
          i += 1
          out.write_char(filter[i].to_int().unsafe_to_char())
        } else if ch == q {
          quote = None
        }
        i += 1
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          out.write_char(ch)
          i += 1
          continue
        }

        if jq_starts_with_at(filter, i, "def") {
          let left_ok = if i == 0 {
            true
          } else {
            not(jq_is_ident_char(filter[i - 1].to_int().unsafe_to_char()))
          }
          let after = i + 3
          let right_ok = if after >= filter.length() {
            true
          } else {
            not(jq_is_ident_char(filter[after].to_int().unsafe_to_char()))
          }
          if left_ok && right_ok {
            out.write_string("def")
            i += 3

            while i < filter.length() {
              let ws = filter[i].to_int().unsafe_to_char()
              if ws == ' ' || ws == '\t' || ws == '\n' || ws == '\r' {
                out.write_char(ws)
                i += 1
              } else {
                break
              }
            }

            while i < filter.length() &&
              jq_is_ident_char(filter[i].to_int().unsafe_to_char()) {
              out.write_char(filter[i].to_int().unsafe_to_char())
              i += 1
            }

            while i < filter.length() {
              let ws = filter[i].to_int().unsafe_to_char()
              if ws == ' ' || ws == '\t' || ws == '\n' || ws == '\r' {
                out.write_char(ws)
                i += 1
              } else {
                break
              }
            }

            if i < filter.length() && filter[i].to_int().unsafe_to_char() == '(' {
              out.write_char('(')
              i += 1
              let mut param_quote : Char? = None
              while i < filter.length() {
                let pch = filter[i].to_int().unsafe_to_char()
                match param_quote {
                  Some(pq) => {
                    out.write_char(pch)
                    if pch == '\\' && i + 1 < filter.length() {
                      i += 1
                      out.write_char(filter[i].to_int().unsafe_to_char())
                    } else if pch == pq {
                      param_quote = None
                    }
                    i += 1
                  }
                  None => {
                    if pch == '"' || pch == '\'' {
                      param_quote = Some(pch)
                      out.write_char(pch)
                      i += 1
                    } else if pch == '$' && i + 1 < filter.length() &&
                      jq_is_ident_start(filter[i + 1].to_int().unsafe_to_char()) {
                      i += 1
                    } else {
                      out.write_char(pch)
                      i += 1
                      if pch == ')' {
                        break
                      }
                    }
                  }
                }
              }
            }
            continue
          }
        }

        out.write_char(ch)
        i += 1
      }
    }
  }
  out.to_string()
}

fn jq_parse_query_with_compat(
  filter : String
) -> (@moonjq.Query?, String) {
  let keys_compat_filter = jq_rewrite_keys_builtin(filter)
  let first = try {
    Some(@moonjq.parse(keys_compat_filter))
  } catch {
    _ => None
  }
  match first {
    Some(query) => (Some(query), "")
    None => {
      let compat_filter = jq_normalize_def_param_dollars(keys_compat_filter)
      if compat_filter == keys_compat_filter {
        return (None, "jq: invalid filter\n")
      }
      let second = try {
        Some(@moonjq.parse(compat_filter))
      } catch {
        _ => None
      }
      match second {
        Some(query) => (Some(query), "")
        None => (None, "jq: invalid filter\n")
      }
    }
  }
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

  let (query_opt, parse_err) = jq_parse_query_with_compat(jq_filter)
  let query = match query_opt {
    Some(q) => q
    None => return @ast.ExecResult::err(parse_err)
  }

  let inputs : Array[Json] = if null_input {
    [Json::null()]
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
    let trimmed = aj_trim(source)
    if slurp {
      if trimmed.length() == 0 {
        [Json::array([])]
      } else {
        let single = try {
          Some(@json.parse(trimmed[:]))
        } catch {
          _ => None
        }
        match single {
          Some(value) => [Json::array([value])]
          None => {
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
          }
        }
      }
    } else {
      if trimmed.length() == 0 {
        [Json::null()]
      } else {
        let single = try {
          Some(@json.parse(trimmed[:]))
        } catch {
          _ => None
        }
        match single {
          Some(value) => [value]
          None => {
            let lines = aj_split_lines_records(source)
            let parsed_lines : Array[Json] = []
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
              parsed_lines.push(parsed)
            }
            if parsed_lines.length() == 0 { [Json::null()] } else { parsed_lines }
          }
        }
      }
    }
  }

  let out = StringBuilder::new()
  for input in inputs {
    let values = try {
      @moonjq.run_json(query, input)
    } catch {
      e => return @ast.ExecResult::err("jq: \{e}\n")
    }
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
  }
  @ast.ExecResult::ok(out.to_string())
}
