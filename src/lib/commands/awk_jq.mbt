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

fn aj_first_line(s : String) -> String {
  let idx = aj_index_of(s, '\n')
  if idx >= 0 {
    aj_substr(s, 0, idx)
  } else {
    s
  }
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

fn awk_eval_getline_command_line(command : String) -> String {
  let cmd = aj_trim(command)
  if not(aj_starts_with(cmd, "echo")) {
    return ""
  }
  let mut rest = if cmd.length() > 4 {
    aj_trim(aj_substr(cmd, 4, cmd.length()))
  } else {
    ""
  }
  if aj_starts_with(rest, "-e ") || aj_starts_with(rest, "-n ") {
    rest = aj_trim(aj_substr(rest, 3, rest.length()))
  }
  if (aj_starts_with(rest, "\"") && aj_ends_with(rest, "\"")) ||
    (aj_starts_with(rest, "'") && aj_ends_with(rest, "'")) {
    rest = aj_decode_c_escapes(aj_substr(rest, 1, rest.length() - 1))
  }
  aj_first_line(rest)
}

fn aj_hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    return Some(ch.to_int() - '0'.to_int())
  }
  if ch >= 'a' && ch <= 'f' {
    return Some(ch.to_int() - 'a'.to_int() + 10)
  }
  if ch >= 'A' && ch <= 'F' {
    return Some(ch.to_int() - 'A'.to_int() + 10)
  }
  None
}

fn aj_octal_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '7' {
    Some(ch.to_int() - '0'.to_int())
  } else {
    None
  }
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
        'a' => { out.write_char('\u0007'); i += 2 }
        'b' => { out.write_char('\u0008'); i += 2 }
        'f' => { out.write_char('\u000c'); i += 2 }
        'v' => { out.write_char('\u000b'); i += 2 }
        '\\' => { out.write_char('\\'); i += 2 }
        '"' => { out.write_char('"'); i += 2 }
        'x' => {
          let mut value = 0
          let mut digits = 0
          let mut j = i + 2
          while j < s.length() && digits < 2 {
            match aj_hex_digit_value(s[j].to_int().unsafe_to_char()) {
              Some(d) => {
                value = value * 16 + d
                digits += 1
                j += 1
              }
              None => break
            }
          }
          if digits > 0 {
            out.write_char(value.unsafe_to_char())
            i = j
          } else {
            out.write_char('x')
            i += 2
          }
        }
        _ => {
          match aj_octal_digit_value(next) {
            Some(first) => {
              let mut value = first
              let mut j = i + 2
              let mut digits = 1
              while j < s.length() && digits < 3 {
                match aj_octal_digit_value(s[j].to_int().unsafe_to_char()) {
                  Some(d) => {
                    value = value * 8 + d
                    digits += 1
                    j += 1
                  }
                  None => break
                }
              }
              out.write_char(value.unsafe_to_char())
              i = j
            }
            None => {
              out.write_char(next)
              i += 2
            }
          }
        }
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
  begin_actions : Array[String]
  pattern : String
  action : String
  end_actions : Array[String]
  has_main : Bool
  range_start : String?
  range_end : String?
}

priv struct AwkFunction {
  params : Array[String]
  body : String
}

let awk_ctrl_next_key = "__moon_bash_awk_ctrl_next"
let awk_ctrl_exit_key = "__moon_bash_awk_ctrl_exit"
let awk_ctrl_error_key = "__moon_bash_awk_ctrl_error"
let awk_ctrl_return_key = "__moon_bash_awk_ctrl_return"
let awk_ctrl_return_value_key = "__moon_bash_awk_ctrl_return_value"
let awk_fn_body_prefix = "__moon_bash_awk_fn_body#"
let awk_fn_params_prefix = "__moon_bash_awk_fn_params#"
let awk_regex_delim_prefix = "__moon_bash_awk_regex_delim__:"

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

fn awk_parse_function_params(param_text : String) -> Array[String] {
  let params : Array[String] = []
  let pieces = awk_split_csv_args(param_text)
  for piece in pieces {
    let name = aj_trim(piece)
    if awk_is_identifier(name) {
      params.push(name)
    }
  }
  params
}

fn awk_take_function_definition(src : String) -> (String?, AwkFunction?, String) {
  let keyword = "function"
  let mut start = -1
  let mut i = 0
  while i + keyword.length() <= src.length() {
    if aj_substr(src, i, i + keyword.length()) == keyword {
      let left_ok = if i == 0 {
        true
      } else {
        not(awk_is_identifier_char(src[i - 1].to_int().unsafe_to_char()))
      }
      if left_ok {
        start = i
        break
      }
    }
    i += 1
  }
  if start < 0 {
    return (None, None, src)
  }

  let mut name_start = start + keyword.length()
  while name_start < src.length() && awk_is_space(src[name_start].to_int().unsafe_to_char()) {
    name_start += 1
  }
  if name_start >= src.length() {
    return (None, None, src)
  }
  let mut name_end = name_start
  while name_end < src.length() && awk_is_identifier_char(src[name_end].to_int().unsafe_to_char()) {
    name_end += 1
  }
  let name = aj_trim(aj_substr(src, name_start, name_end))
  if not(awk_is_identifier(name)) {
    return (None, None, src)
  }

  let mut open_paren = name_end
  while open_paren < src.length() && awk_is_space(src[open_paren].to_int().unsafe_to_char()) {
    open_paren += 1
  }
  if open_paren >= src.length() || src[open_paren].to_int().unsafe_to_char() != '(' {
    return (None, None, src)
  }

  let mut paren_depth = 1
  let mut close_paren = open_paren + 1
  let mut quote : Char? = None
  while close_paren < src.length() && paren_depth > 0 {
    let ch = src[close_paren].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && close_paren + 1 < src.length() {
          close_paren += 2
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
        } else if ch == ')' {
          paren_depth -= 1
        }
      }
    }
    if paren_depth > 0 {
      close_paren += 1
    }
  }
  if paren_depth != 0 || close_paren >= src.length() {
    return (None, None, src)
  }

  let params_text = aj_substr(src, open_paren + 1, close_paren)
  let params = awk_parse_function_params(params_text)

  let mut open_brace = close_paren + 1
  while open_brace < src.length() && awk_is_space(src[open_brace].to_int().unsafe_to_char()) {
    open_brace += 1
  }
  if open_brace >= src.length() || src[open_brace].to_int().unsafe_to_char() != '{' {
    return (None, None, src)
  }

  let mut brace_depth = 1
  let mut close_brace = open_brace + 1
  quote = None
  while close_brace < src.length() && brace_depth > 0 {
    let ch = src[close_brace].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && close_brace + 1 < src.length() {
          close_brace += 2
          continue
        }
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
        } else if ch == '{' {
          brace_depth += 1
        } else if ch == '}' {
          brace_depth -= 1
        }
      }
    }
    if brace_depth > 0 {
      close_brace += 1
    }
  }
  if brace_depth != 0 || close_brace >= src.length() {
    return (None, None, src)
  }

  let body = aj_substr(src, open_brace + 1, close_brace)
  let remaining = aj_substr(src, 0, start) + aj_substr(src, close_brace + 1, src.length())
  (
    Some(name),
    Some({
      params,
      body,
    }),
    remaining,
  )
}

fn awk_extract_functions(src : String) -> (String, Map[String, AwkFunction]) {
  let functions : Map[String, AwkFunction] = {}
  let mut remaining = src
  while true {
    match awk_take_function_definition(remaining) {
      (Some(name), Some(def), rest) => {
        functions[name] = def
        remaining = rest
      }
      _ => break
    }
  }
  (remaining, functions)
}

fn awk_fn_body_key(name : String) -> String {
  awk_fn_body_prefix + name
}

fn awk_fn_params_key(name : String) -> String {
  awk_fn_params_prefix + name
}

fn awk_install_functions(vars : Map[String, String], functions : Map[String, AwkFunction]) -> Unit {
  for name, def in functions {
    vars[awk_fn_body_key(name)] = def.body
    vars[awk_fn_params_key(name)] = def.params.join(",")
  }
}

fn awk_get_function(vars : Map[String, String], name : String) -> AwkFunction? {
  match (vars.get(awk_fn_body_key(name)), vars.get(awk_fn_params_key(name))) {
    (Some(body), Some(raw_params)) => {
      let params : Array[String] = []
      if raw_params.length() > 0 {
        let pieces = aj_split_by_delim(raw_params, ",")
        for piece in pieces {
          let p = aj_trim(piece)
          if awk_is_identifier(p) {
            params.push(p)
          }
        }
      }
      Some({ params, body })
    }
    _ => None
  }
}

fn awk_parse_call_expr(expr : String) -> (String, Array[String])? {
  let t = aj_trim(expr)
  if t.length() < 3 {
    return None
  }
  let open_paren = aj_index_of(t, '(')
  if open_paren <= 0 || t[t.length() - 1].to_int().unsafe_to_char() != ')' {
    return None
  }
  let name = aj_trim(aj_substr(t, 0, open_paren))
  if not(awk_is_identifier(name)) {
    return None
  }
  let mut depth = 1
  let mut quote : Char? = None
  let mut i = open_paren + 1
  while i < t.length() && depth > 0 {
    let ch = t[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < t.length() {
          i += 2
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
        }
      }
    }
    if depth > 0 {
      i += 1
    }
  }
  if depth != 0 || i != t.length() - 1 {
    return None
  }
  let args = awk_split_csv_args(aj_substr(t, open_paren + 1, i))
  Some((name, args))
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

fn awk_strip_comments(src : String) -> String {
  let out = StringBuilder::new()
  let mut quote : Char? = None
  let mut in_regex = false
  let mut escaped = false
  let mut i = 0
  while i < src.length() {
    let ch = src[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        out.write_char(ch)
        if ch == '\\' && i + 1 < src.length() {
          i += 1
          out.write_char(src[i].to_int().unsafe_to_char())
        } else if ch == q {
          quote = None
        }
      }
      None => {
        if in_regex {
          out.write_char(ch)
          if escaped {
            escaped = false
          } else if ch == '\\' {
            escaped = true
          } else if ch == '/' {
            in_regex = false
          }
        } else if ch == '"' || ch == '\'' {
          quote = Some(ch)
          out.write_char(ch)
        } else if ch == '/' {
          in_regex = true
          escaped = false
          out.write_char(ch)
        } else if ch == '#' {
          while i < src.length() && src[i].to_int().unsafe_to_char() != '\n' {
            i += 1
          }
          if i < src.length() && src[i].to_int().unsafe_to_char() == '\n' {
            out.write_char('\n')
          }
        } else {
          out.write_char(ch)
        }
      }
    }
    i += 1
  }
  out.to_string()
}

fn awk_parse_program(src : String) -> AwkProgram {
  let src = awk_strip_comments(src)
  let begin_actions : Array[String] = []
  let mut rest_after_begin = src
  while true {
    let (block, next) = awk_take_named_block(rest_after_begin, "BEGIN")
    match block {
      Some(action) => {
        begin_actions.push(action)
        rest_after_begin = next
      }
      None => break
    }
  }

  let end_actions : Array[String] = []
  let mut rest_after_end = rest_after_begin
  while true {
    let (block, next) = awk_take_named_block(rest_after_end, "END")
    match block {
      Some(action) => {
        end_actions.push(action)
        rest_after_end = next
      }
      None => break
    }
  }
  let rest = aj_trim(rest_after_end)

  if rest.length() == 0 {
    return {
      begin_actions,
      pattern: "",
      action: "",
      end_actions,
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
      begin_actions,
      pattern,
      action: "",
      end_actions,
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
    begin_actions,
    pattern,
    action,
    end_actions,
    has_main: true,
    range_start,
    range_end,
  }
}

fn awk_split_fields(line : String, fs : String) -> Array[String] {
  if fs == "." {
    return []
  }
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
  let mut seen_exp = false
  let mut seen_exp_digit = false
  while i < t.length() {
    let ch = t[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      seen_digit = true
      if seen_exp {
        seen_exp_digit = true
      }
      i += 1
      continue
    }
    if ch == '.' && not(seen_dot) && not(seen_exp) {
      seen_dot = true
      i += 1
      continue
    }
    if (ch == 'e' || ch == 'E') && seen_digit && not(seen_exp) {
      seen_exp = true
      seen_exp_digit = false
      i += 1
      if i < t.length() {
        let sign = t[i].to_int().unsafe_to_char()
        if sign == '+' || sign == '-' {
          i += 1
        }
      }
      continue
    }
    return false
  }
  if seen_exp {
    seen_digit && seen_exp_digit
  } else {
    seen_digit
  }
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

  let mut value = 0.0
  while i < t.length() {
    let ch = t[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      value = value * 10.0 + (ch.to_int() - '0'.to_int()).to_double()
      i += 1
    } else {
      break
    }
  }

  if i < t.length() && t[i].to_int().unsafe_to_char() == '.' {
    i += 1
    let mut factor = 0.1
    while i < t.length() {
      let ch = t[i].to_int().unsafe_to_char()
      if ch >= '0' && ch <= '9' {
        value += (ch.to_int() - '0'.to_int()).to_double() * factor
        factor /= 10.0
        i += 1
      } else {
        break
      }
    }
  }
  if i < t.length() && (t[i].to_int().unsafe_to_char() == 'e' || t[i].to_int().unsafe_to_char() == 'E') {
    i += 1
    let mut exp_sign = 1
    if i < t.length() {
      let exp_sign_ch = t[i].to_int().unsafe_to_char()
      if exp_sign_ch == '-' {
        exp_sign = -1
        i += 1
      } else if exp_sign_ch == '+' {
        i += 1
      }
    }
    let mut exp = 0
    while i < t.length() {
      let exp_ch = t[i].to_int().unsafe_to_char()
      if exp_ch >= '0' && exp_ch <= '9' {
        exp = exp * 10 + (exp_ch.to_int() - '0'.to_int())
        i += 1
      } else {
        break
      }
    }
    value = value * @math.pow(10.0, (exp_sign * exp).to_double())
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

fn awk_collect_array_namespace(
  array_vars : Map[String, String],
  ns_name : String
) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  let prefix = ns_name + "#"
  for key, value in array_vars {
    if aj_starts_with(key, prefix) {
      entries.push((key, value))
    }
  }
  entries
}

fn awk_remove_array_namespace(array_vars : Map[String, String], ns_name : String) -> Unit {
  let entries = awk_collect_array_namespace(array_vars, ns_name)
  for entry in entries {
    array_vars.remove(entry.0)
  }
}

fn awk_copy_array_namespace(
  array_vars : Map[String, String],
  source_name : String,
  target_name : String
) -> Unit {
  awk_remove_array_namespace(array_vars, target_name)
  let source_prefix = source_name + "#"
  let target_prefix = target_name + "#"
  let entries = awk_collect_array_namespace(array_vars, source_name)
  for entry in entries {
    let suffix = aj_substr(entry.0, source_prefix.length(), entry.0.length())
    array_vars[target_prefix + suffix] = entry.1
  }
}

fn awk_function_param_is_array(fn_def : AwkFunction, param : String) -> Bool {
  let needle = param + "["
  if aj_find_substring(fn_def.body, needle) >= 0 {
    return true
  }
  aj_find_substring(fn_def.body, " in " + param) >= 0
}

fn awk_to_lower(s : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 32).unsafe_to_char())
    } else if ch == 'Ä' {
      out.write_char('ä')
    } else if ch == 'Ö' {
      out.write_char('ö')
    } else if ch == 'Ü' {
      out.write_char('ü')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

fn awk_to_upper(s : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'a' && ch <= 'z' {
      out.write_char((ch.to_int() - 32).unsafe_to_char())
    } else if ch == 'ä' {
      out.write_char('Ä')
    } else if ch == 'ö' {
      out.write_char('Ö')
    } else if ch == 'ü' {
      out.write_char('Ü')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
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
  let is_regex = aj_starts_with(delim, awk_regex_delim_prefix)
  let delim = if is_regex {
    aj_substr(delim, awk_regex_delim_prefix.length(), delim.length())
  } else {
    delim
  }
  if delim.length() == 0 {
    return awk_split_chars(source)
  }
  if delim == " " && not(is_regex) {
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
    return awk_regex_delim_prefix + aj_substr(text, 1, text.length() - 1)
  }
  awk_eval_expr(text, line, fields, nr, nf, vars, array_vars)
}

fn awk_eval_sub_pattern(
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
  if pattern.length() >= 2 &&
    pattern[0].to_int().unsafe_to_char() == '[' &&
    pattern[pattern.length() - 1].to_int().unsafe_to_char() == ']' {
    let class_chars = aj_substr(pattern, 1, pattern.length() - 1)
    for i = 0; i < source.length(); i = i + 1 {
      let ch = source[i].to_int().unsafe_to_char()
      if aj_find_substring(class_chars, ch.to_string()) >= 0 {
        let updated = aj_substr(source, 0, i) +
          replacement +
          aj_substr(source, i + 1, source.length())
        return (updated, 1)
      }
    }
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
  if pattern.length() >= 2 &&
    pattern[0].to_int().unsafe_to_char() == '[' &&
    pattern[pattern.length() - 1].to_int().unsafe_to_char() == ']' {
    let class_chars = aj_substr(pattern, 1, pattern.length() - 1)
    let out = StringBuilder::new()
    let mut count = 0
    for i = 0; i < source.length(); i = i + 1 {
      let ch = source[i].to_int().unsafe_to_char()
      if aj_find_substring(class_chars, ch.to_string()) >= 0 {
        out.write_string(replacement)
        count += 1
      } else {
        out.write_char(ch)
      }
    }
    return (out.to_string(), count)
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
  let mut paren_depth = 0
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
        if ch == '(' {
          paren_depth += 1
          i += 1
          continue
        }
        if ch == ')' && paren_depth > 0 {
          paren_depth -= 1
          i += 1
          continue
        }
        if bracket_depth == 0 && paren_depth == 0 {
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
  let mut paren_depth = 0
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
        } else if ch == '(' {
          paren_depth += 1
        } else if ch == ')' && paren_depth > 0 {
          paren_depth -= 1
        } else if ch == '[' {
          bracket_depth += 1
        } else if ch == ']' && bracket_depth > 0 {
          bracket_depth -= 1
        } else if bracket_depth == 0 && paren_depth == 0 {
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
    let key_expr = aj_substr(t, 1, t.length())
    if key_expr == "0" {
      return line
    }
    let key_value = if key_expr == "NF" {
      fields.length().to_string()
    } else if awk_is_numeric_string(key_expr) {
      awk_number_to_string(awk_parse_number(key_expr))
    } else {
      awk_eval_expr(key_expr, line, fields, nr, nf, vars, array_vars)
    }
    if key_value == "NF" {
      return if fields.length() == 0 { "" } else { fields[fields.length() - 1] }
    } else {
      let idx = awk_parse_number(key_value).to_int()
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

fn awk_execute_function_body(
  body : String,
  line : String,
  fields : Array[String],
  nr : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> Unit {
  let statements = awk_merge_if_else_statements(awk_split_statements(body))
  for stmt_raw in statements {
    if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_return_key) {
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
          if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_return_key) {
            break
          }
          vars[loop_var] = idx_value
          if body_stmt.length() > 0 {
            awk_execute_function_body(body_stmt, line, fields, nr, vars, array_vars, out)
          }
        }
        continue
      }
      None => ()
    }

    match awk_parse_for_statement(stmt) {
      Some((init_stmt, cond_expr, update_stmt, body_stmt)) => {
        if init_stmt.length() > 0 {
          ignore(awk_eval_expr(init_stmt, line, fields, nr, fields.length(), vars, array_vars))
        }
        let mut loop_count = 0
        while true {
          if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_return_key) {
            break
          }
          if cond_expr.length() > 0 &&
            not(
              awk_eval_condition(
                cond_expr,
                line,
                fields,
                nr,
                fields.length(),
                vars,
                array_vars,
              ),
            ) {
            break
          }
          if body_stmt.length() > 0 {
            awk_execute_function_body(body_stmt, line, fields, nr, vars, array_vars, out)
          }
          if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_return_key) {
            break
          }
          if update_stmt.length() > 0 {
            ignore(
              awk_eval_expr(
                update_stmt,
                line,
                fields,
                nr,
                fields.length(),
                vars,
                array_vars,
              ),
            )
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
        let (then_body, else_body) = awk_split_if_else_body(body_stmt)
        if awk_eval_condition(
          cond_expr,
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
        ) {
          awk_execute_function_body(then_body, line, fields, nr, vars, array_vars, out)
        } else {
          match else_body {
            Some(else_stmt) =>
              awk_execute_function_body(else_stmt, line, fields, nr, vars, array_vars, out)
            None => ()
          }
        }
        continue
      }
      None => ()
    }

    if stmt == "return" || aj_starts_with(stmt, "return ") || aj_starts_with(stmt, "return(") {
      let expr = if stmt.length() > 6 { aj_trim(aj_substr(stmt, 6, stmt.length())) } else { "" }
      let value = if expr.length() == 0 {
        ""
      } else {
        awk_eval_expr(expr, line, fields, nr, fields.length(), vars, array_vars)
      }
      vars[awk_ctrl_return_key] = "1"
      vars[awk_ctrl_return_value_key] = value
      break
    }

    if stmt == "exit" || aj_starts_with(stmt, "exit ") || aj_starts_with(stmt, "exit(") {
      let code_expr = if stmt.length() > 4 { aj_trim(aj_substr(stmt, 4, stmt.length())) } else { "" }
      let code = if code_expr.length() == 0 {
        0
      } else {
        awk_eval_number(code_expr, line, fields, nr, fields.length(), vars, array_vars).to_int()
      }
      vars[awk_ctrl_exit_key] = code.to_string()
      break
    }

    if aj_starts_with(stmt, "print") {
      let rest = aj_trim(aj_substr(stmt, 5, stmt.length()))
      out.write_string(
        awk_render_print_output(
          rest,
          line,
          fields,
          nr,
          vars,
          array_vars,
        ),
      )
      continue
    }

    let plus_eq_idx = awk_find_top_level_token(stmt, "+=")
    if plus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, plus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, plus_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        line,
        fields,
        nr,
        fields.length(),
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
              line,
              fields,
              nr,
              fields.length(),
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

    let eq_idx = awk_find_top_level_token(stmt, "=")
    if eq_idx > 0 {
      let prev = stmt[eq_idx - 1].to_int().unsafe_to_char()
      let next = if eq_idx + 1 < stmt.length() {
        Some(stmt[eq_idx + 1].to_int().unsafe_to_char())
      } else {
        None
      }
      if prev != '!' && prev != '<' && prev != '>' && prev != '=' &&
        next != Some('=') {
        let lhs = aj_trim(aj_substr(stmt, 0, eq_idx))
        let rhs = aj_trim(aj_substr(stmt, eq_idx + 1, stmt.length()))
        let value = awk_eval_expr(rhs, line, fields, nr, fields.length(), vars, array_vars)
        if awk_is_identifier(lhs) {
          vars[lhs] = value
        } else {
          match awk_parse_array_ref(lhs) {
            Some((arr_name, idx_expr)) => {
              let idx = awk_eval_expr(
                idx_expr,
                line,
                fields,
                nr,
                fields.length(),
                vars,
                array_vars,
              )
              array_vars[awk_array_key(arr_name, idx)] = value
            }
            None => ()
          }
        }
      }
      continue
    }

    match awk_parse_call_expr(stmt) {
      Some((call_name, args)) => {
        if call_name == "close" {
          continue
        }
        if call_name == "sprintf" {
          ignore(awk_eval_expr(stmt, line, fields, nr, fields.length(), vars, array_vars))
          continue
        }
        ignore(awk_eval_user_function(
          call_name,
          args,
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
          out,
        ))
        continue
      }
      None => ()
    }
  }
}

fn awk_eval_user_function(
  fn_name : String,
  arg_exprs : Array[String],
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> String {
  ignore(nf)
  let fn_def = match awk_get_function(vars, fn_name) {
    Some(def) => def
    None => return ""
  }

  let saved_scalars : Array[(String, String?)] = []
  let array_bindings : Array[(String, String)] = []
  for i = 0; i < fn_def.params.length(); i = i + 1 {
    let param = fn_def.params[i]
    saved_scalars.push((param, vars.get(param)))
    if i < arg_exprs.length() {
      let arg_expr = aj_trim(arg_exprs[i])
      if awk_is_identifier(arg_expr) && awk_function_param_is_array(fn_def, param) {
        array_bindings.push((param, arg_expr))
        awk_copy_array_namespace(array_vars, arg_expr, param)
        vars[param] = ""
      } else {
        vars[param] = awk_eval_expr(
          arg_expr,
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
        )
      }
    } else {
      vars[param] = ""
    }
  }

  vars.remove(awk_ctrl_return_key)
  vars.remove(awk_ctrl_return_value_key)
  awk_execute_function_body(fn_def.body, line, fields, nr, vars, array_vars, out)
  let return_value = vars.get(awk_ctrl_return_value_key).unwrap_or("")
  vars.remove(awk_ctrl_return_key)
  vars.remove(awk_ctrl_return_value_key)

  for binding in array_bindings {
    let local_name = binding.0
    let actual_name = binding.1
    awk_remove_array_namespace(array_vars, actual_name)
    awk_copy_array_namespace(array_vars, local_name, actual_name)
    awk_remove_array_namespace(array_vars, local_name)
  }

  for saved in saved_scalars {
    match saved.1 {
      Some(v) => vars[saved.0] = v
      None => vars.remove(saved.0)
    }
  }

  return_value
}

fn awk_bool_to_string(value : Bool) -> String {
  if value { "1" } else { "0" }
}

fn awk_compare_strings(left : String, right : String) -> Int {
  let shared = if left.length() < right.length() { left.length() } else { right.length() }
  for i = 0; i < shared; i = i + 1 {
    let lch = left[i].to_int().unsafe_to_char()
    let rch = right[i].to_int().unsafe_to_char()
    if lch < rch {
      return -1
    }
    if lch > rch {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

fn awk_compare_values(left : String, right : String, op : String) -> Bool {
  if awk_is_numeric_string(left) && awk_is_numeric_string(right) {
    let lnum = awk_parse_number(left)
    let rnum = awk_parse_number(right)
    match op {
      "==" => lnum == rnum
      "!=" => lnum != rnum
      ">=" => lnum >= rnum
      "<=" => lnum <= rnum
      ">" => lnum > rnum
      "<" => lnum < rnum
      _ => false
    }
  } else {
    let cmp = awk_compare_strings(left, right)
    match op {
      "==" => cmp == 0
      "!=" => cmp != 0
      ">=" => cmp >= 0
      "<=" => cmp <= 0
      ">" => cmp > 0
      "<" => cmp < 0
      _ => false
    }
  }
}

fn awk_value_truthy(value : String) -> Bool {
  if awk_is_numeric_string(value) {
    awk_parse_number(value) != 0.0
  } else {
    value.length() > 0
  }
}

fn awk_assign_reference(
  target : String,
  value : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> Bool {
  if awk_is_identifier(target) {
    vars[target] = value
    return true
  }
  match awk_parse_array_ref(target) {
    Some((arr_name, idx_expr)) => {
      let idx = awk_eval_expr(idx_expr, line, fields, nr, nf, vars, array_vars)
      array_vars[awk_array_key(arr_name, idx)] = value
      true
    }
    None => false
  }
}

fn awk_mutate_numeric_reference(
  target : String,
  delta : Double,
  return_new : Bool,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String? {
  if awk_is_identifier(target) {
    let old = awk_parse_number(vars.get(target).unwrap_or(""))
    let updated = old + delta
    vars[target] = awk_number_to_string(updated)
    return Some(if return_new { vars[target] } else { awk_number_to_string(old) })
  }
  if aj_starts_with(target, "$") && target.length() > 1 {
    let key_expr = aj_substr(target, 1, target.length())
    let key_value = if key_expr == "NF" {
      fields.length().to_string()
    } else {
      awk_eval_expr(key_expr, line, fields, nr, nf, vars, array_vars)
    }
    let idx = awk_parse_number(key_value).to_int()
    if idx > 0 {
      while fields.length() < idx {
        fields.push("")
      }
      let old = awk_parse_number(fields[idx - 1])
      let updated = old + delta
      fields[idx - 1] = awk_number_to_string(updated)
      return Some(if return_new { fields[idx - 1] } else { awk_number_to_string(old) })
    }
  }
  match awk_parse_array_ref(target) {
    Some((arr_name, idx_expr)) => {
      let idx = awk_eval_expr(idx_expr, line, fields, nr, nf, vars, array_vars)
      let key = awk_array_key(arr_name, idx)
      let old = awk_parse_number(array_vars.get(key).unwrap_or(""))
      let updated = old + delta
      array_vars[key] = awk_number_to_string(updated)
      Some(if return_new { array_vars.get(key).unwrap_or("") } else { awk_number_to_string(old) })
    }
    None => None
  }
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
  let t = awk_strip_outer_parens(aj_trim(expr))
  let tokens = awk_tokenize_expr(t)
  if tokens.length() == 0 {
    return ""
  }

  if aj_ends_with(t, "++") || aj_ends_with(t, "--") {
    let target = aj_trim(aj_substr(t, 0, t.length() - 2))
    let delta = if aj_ends_with(t, "++") { 1.0 } else { -1.0 }
    match awk_mutate_numeric_reference(
      target,
      delta,
      false,
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    ) {
      Some(value) => return value
      None => ()
    }
  }

  if aj_starts_with(t, "++") || aj_starts_with(t, "--") {
    let target = aj_trim(aj_substr(t, 2, t.length()))
    let delta = if aj_starts_with(t, "++") { 1.0 } else { -1.0 }
    match awk_mutate_numeric_reference(
      target,
      delta,
      true,
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    ) {
      Some(value) => return value
      None => ()
    }
  }

  match awk_parse_call_expr(t) {
    Some((call_name, args)) => {
      if call_name == "index" {
        if args.length() < 2 {
          return "0"
        }
        let haystack = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        let needle = awk_eval_expr(
          args[1],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        if needle.length() == 0 {
          return "1"
        }
        let idx = aj_find_substring(haystack, needle)
        return if idx >= 0 { (idx + 1).to_string() } else { "0" }
      }

      if call_name == "substr" {
        if args.length() < 2 {
          return ""
        }
        let text = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        let raw_start = awk_eval_number(
          args[1],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        ).to_int()
        let start_pos = if raw_start <= 1 { 1 } else { raw_start }
        let start_idx = start_pos - 1
        if start_idx >= text.length() {
          return ""
        }
        if args.length() >= 3 {
          let len = awk_eval_number(
            args[2],
            line,
            fields,
            nr,
            nf,
            vars,
            array_vars,
          ).to_int()
          if len <= 0 {
            return ""
          }
          return aj_substr(text, start_idx, start_idx + len)
        }
        return aj_substr(text, start_idx, text.length())
      }

      if call_name == "tolower" {
        if args.length() == 0 {
          return ""
        }
        let value = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        return awk_to_lower(value)
      }

      if call_name == "toupper" {
        if args.length() == 0 {
          return ""
        }
        let value = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        return awk_to_upper(value)
      }

      if call_name == "close" {
        return "0"
      }

      if call_name == "sin" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.sin(value))
      }

      if call_name == "cos" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.cos(value))
      }

      if call_name == "exp" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.exp(value))
      }

      if call_name == "log" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.ln(value))
      }

      if call_name == "sqrt" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(value.sqrt())
      }

      if call_name == "atan2" {
        if args.length() < 2 {
          return "0"
        }
        let y = awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        let x = awk_eval_number(args[1], line, fields, nr, nf, vars, array_vars)
        let pi = @math.atan(1.0) * 4.0
        let half_pi = pi / 2.0
        let angle = if x > 0.0 {
          @math.atan(y / x)
        } else if x < 0.0 && y >= 0.0 {
          @math.atan(y / x) + pi
        } else if x < 0.0 {
          @math.atan(y / x) - pi
        } else if y > 0.0 {
          half_pi
        } else if y < 0.0 {
          -half_pi
        } else {
          0.0
        }
        return awk_number_to_string(angle)
      }

      match awk_get_function(vars, call_name) {
        Some(_) => {
          let fn_out = StringBuilder::new()
          return awk_eval_user_function(
            call_name,
            args,
            line,
            fields,
            nr,
            nf,
            vars,
            array_vars,
            fn_out,
          )
        }
        None => ()
      }
    }
    None => ()
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

  let eq_idx = awk_find_top_level_token(t, "=")
  if eq_idx > 0 {
    let prev = t[eq_idx - 1].to_int().unsafe_to_char()
    let next = if eq_idx + 1 < t.length() {
      Some(t[eq_idx + 1].to_int().unsafe_to_char())
    } else {
      None
    }
    if prev != '!' && prev != '<' && prev != '>' && prev != '=' &&
      next != Some('=') {
      let lhs = aj_trim(aj_substr(t, 0, eq_idx))
      let rhs = aj_trim(aj_substr(t, eq_idx + 1, t.length()))
      let value = awk_eval_expr(rhs, line, fields, nr, nf, vars, array_vars)
      if awk_assign_reference(lhs, value, line, fields, nr, nf, vars, array_vars) {
        return value
      }
    }
  }

  let in_idx = awk_find_top_level_token(t, " in ")
  if in_idx > 0 {
    let left_expr = aj_substr(t, 0, in_idx)
    let right_expr = aj_trim(aj_substr(t, in_idx + 4, t.length()))
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
      return awk_bool_to_string(array_vars.contains(awk_array_key(right_expr, idx_value)))
    }
  }

  let comma_idx = awk_find_top_level_token(t, ",")
  if comma_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, comma_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, comma_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let subsep = vars.get("SUBSEP").unwrap_or("\u001c")
    return left + subsep + right
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

  let or_idx = awk_find_top_level_token(t, "||")
  if or_idx > 0 {
    let left_value = awk_eval_expr(
      aj_substr(t, 0, or_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if awk_value_truthy(left_value) {
      return "1"
    }
    let right_value = awk_eval_expr(
      aj_substr(t, or_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_value_truthy(right_value))
  }

  let and_idx = awk_find_top_level_token(t, "&&")
  if and_idx > 0 {
    let left_value = awk_eval_expr(
      aj_substr(t, 0, and_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if not(awk_value_truthy(left_value)) {
      return "0"
    }
    let right_value = awk_eval_expr(
      aj_substr(t, and_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_value_truthy(right_value))
  }

  let not_match_idx = awk_find_top_level_token(t, "!~")
  if not_match_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, not_match_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right_expr = aj_trim(aj_substr(t, not_match_idx + 2, t.length()))
    let right = if aj_starts_with(right_expr, "/") && aj_ends_with(right_expr, "/") {
      right_expr
    } else {
      "/" + awk_eval_expr(right_expr, line, fields, nr, nf, vars, array_vars) + "/"
    }
    let (rstart, _rlength) = awk_find_regex_match_range(right, left)
    return awk_bool_to_string(rstart <= 0)
  }

  let match_idx = awk_find_top_level_token(t, "~")
  if match_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, match_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right_expr = aj_trim(aj_substr(t, match_idx + 1, t.length()))
    let right = if aj_starts_with(right_expr, "/") && aj_ends_with(right_expr, "/") {
      right_expr
    } else {
      "/" + awk_eval_expr(right_expr, line, fields, nr, nf, vars, array_vars) + "/"
    }
    let (rstart, _rlength) = awk_find_regex_match_range(right, left)
    return awk_bool_to_string(rstart > 0)
  }

  let mut cmp_idx = awk_find_top_level_token(t, "==")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "=="))
  }

  cmp_idx = awk_find_top_level_token(t, "!=")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "!="))
  }

  cmp_idx = awk_find_top_level_token(t, ">=")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, ">="))
  }

  cmp_idx = awk_find_top_level_token(t, "<=")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "<="))
  }

  cmp_idx = awk_find_top_level_token(t, ">")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, ">"))
  }

  cmp_idx = awk_find_top_level_token(t, "<")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "<"))
  }

  let pow_idx = awk_find_top_level_token(t, "^")
  if pow_idx > 0 {
    let left = awk_eval_number(
      aj_substr(t, 0, pow_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(t, pow_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_number_to_string(@math.pow(left, right))
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

  let mul_div_idx = awk_find_top_level_operator(t, "*/%")
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
    if op == '%' {
      if right == 0.0 {
        return "0"
      }
      let left_i = left.to_int()
      let right_i = right.to_int()
      if right_i == 0 {
        return "0"
      }
      return (left_i % right_i).to_string()
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
  let mut rest = aj_trim(aj_substr(action, 6, action.length()))
  if rest.length() == 0 {
    return ("", [])
  }
  if rest.length() >= 2 &&
    rest[0].to_int().unsafe_to_char() == '(' &&
    rest[rest.length() - 1].to_int().unsafe_to_char() == ')' {
    rest = aj_trim(aj_substr(rest, 1, rest.length() - 1))
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

fn awk_pow10_int(exp : Int) -> Int {
  let mut out = 1
  let mut i = 0
  let limit = if exp < 0 { 0 } else if exp > 9 { 9 } else { exp }
  while i < limit {
    out *= 10
    i += 1
  }
  out
}

fn awk_to_hex_string(value : Int) -> String {
  if value == 0 {
    return "0"
  }
  let hex = "0123456789abcdef"
  let chars : Array[Char] = []
  let mut v = if value < 0 { -value } else { value }
  while v > 0 {
    let digit = v % 16
    chars.push(hex[digit].to_int().unsafe_to_char())
    v /= 16
  }
  let out = StringBuilder::new()
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    out.write_char(chars[i])
  }
  out.to_string()
}

fn awk_pad_left(text : String, width : Int, pad : Char) -> String {
  if width <= text.length() {
    return text
  }
  let out = StringBuilder::new()
  let mut remaining = width - text.length()
  while remaining > 0 {
    out.write_char(pad)
    remaining -= 1
  }
  out.write_string(text)
  out.to_string()
}

fn awk_pad_right(text : String, width : Int, pad : Char) -> String {
  if width <= text.length() {
    return text
  }
  let out = StringBuilder::new()
  out.write_string(text)
  let mut remaining = width - text.length()
  while remaining > 0 {
    out.write_char(pad)
    remaining -= 1
  }
  out.to_string()
}

fn awk_apply_printf_width(
  text : String,
  width : Int,
  left_align : Bool,
  zero_pad : Bool
) -> String {
  if width <= text.length() {
    return text
  }
  if left_align {
    return awk_pad_right(text, width, ' ')
  }
  if zero_pad && text.length() > 0 {
    let first = text[0].to_int().unsafe_to_char()
    if first == '+' || first == '-' || first == ' ' {
      return first.to_string() + awk_pad_left(aj_substr(text, 1, text.length()), width - 1, '0')
    }
  }
  awk_pad_left(text, width, if zero_pad { '0' } else { ' ' })
}

fn awk_format_fixed_number(
  raw : Double,
  precision : Int,
  plus_sign : Bool,
  space_sign : Bool
) -> String {
  let mut precision = precision
  if precision < 0 {
    precision = 6
  } else if precision > 9 {
    precision = 9
  }
  let scale = @math.pow(10.0, precision.to_double())
  let rounded = if raw >= 0.0 {
    (raw * scale + 0.5).to_int()
  } else {
    (raw * scale - 0.5).to_int()
  }
  let negative = rounded < 0
  let abs_scaled = if rounded < 0 { -rounded } else { rounded }
  let pow10 = awk_pow10_int(precision)
  let whole = if precision == 0 { abs_scaled } else { abs_scaled / pow10 }
  let frac = if precision == 0 { 0 } else { abs_scaled % pow10 }
  let sign = if negative {
    "-"
  } else if plus_sign {
    "+"
  } else if space_sign {
    " "
  } else {
    ""
  }
  if precision == 0 {
    return sign + whole.to_string()
  }
  let frac_text = frac.to_string()
  let frac_padded = awk_pad_left(frac_text, precision, '0')
  sign + whole.to_string() + "." + frac_padded
}

fn awk_trim_trailing_fraction_zeros(text : String) -> String {
  let dot = aj_index_of(text, '.')
  if dot < 0 {
    return text
  }
  let mut end_ = text.length()
  while end_ > dot + 1 && text[end_ - 1].to_int().unsafe_to_char() == '0' {
    end_ -= 1
  }
  if end_ == dot + 1 {
    end_ -= 1
  }
  aj_substr(text, 0, end_)
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
      let mut left_align = false
      let mut plus_sign = false
      let mut space_sign = false
      let mut zero_pad = false
      while j < decoded.length() {
        let f = decoded[j].to_int().unsafe_to_char()
        if f == '-' {
          left_align = true
          j += 1
        } else if f == '+' {
          plus_sign = true
          j += 1
        } else if f == ' ' {
          space_sign = true
          j += 1
        } else if f == '0' {
          zero_pad = true
          j += 1
        } else {
          break
        }
      }
      let mut width = 0
      if j < decoded.length() && decoded[j].to_int().unsafe_to_char() == '*' {
        width = if arg_idx < args.length() { awk_parse_number(args[arg_idx]).to_int() } else { 0 }
        arg_idx += 1
        j += 1
      } else {
        while j < decoded.length() {
          let wch = decoded[j].to_int().unsafe_to_char()
          if wch >= '0' && wch <= '9' {
            width = width * 10 + (wch.to_int() - '0'.to_int())
            j += 1
          } else {
            break
          }
        }
      }
      if width < 0 {
        left_align = true
        width = -width
      }
      if width > 10000 {
        width = 10000
      }
      let mut precision = -1
      if j < decoded.length() && decoded[j].to_int().unsafe_to_char() == '.' {
        j += 1
        if j < decoded.length() && decoded[j].to_int().unsafe_to_char() == '*' {
          precision = if arg_idx < args.length() { awk_parse_number(args[arg_idx]).to_int() } else { 0 }
          arg_idx += 1
          j += 1
        } else {
          precision = 0
          while j < decoded.length() {
            let pch = decoded[j].to_int().unsafe_to_char()
            if pch >= '0' && pch <= '9' {
              precision = precision * 10 + (pch.to_int() - '0'.to_int())
              j += 1
            } else {
              break
            }
          }
        }
        if precision > 1000 {
          precision = 1000
        }
      }
      if j >= decoded.length() {
        out.write_char('%')
        i += 1
        continue
      }
      let spec = decoded[j].to_int().unsafe_to_char()
      let raw = if arg_idx < args.length() { args[arg_idx] } else { "" }
      if spec == 's' {
        let mut value = raw
        if precision >= 0 && precision < value.length() {
          value = aj_substr(value, 0, precision)
        }
        out.write_string(awk_apply_printf_width(value, width, left_align, false))
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'd' || spec == 'i' {
        let num = awk_parse_number(raw).to_int()
        let negative = num < 0
        let mut digits = if num < 0 { (-num).to_string() } else { num.to_string() }
        if precision == 0 && num == 0 {
          digits = ""
        }
        if precision > 0 {
          digits = awk_pad_left(digits, precision, '0')
        }
        let sign = if negative {
          "-"
        } else if plus_sign {
          "+"
        } else if space_sign {
          " "
        } else {
          ""
        }
        let text = sign + digits
        out.write_string(
          awk_apply_printf_width(text, width, left_align, zero_pad && precision < 0),
        )
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'x' || spec == 'X' {
        let num = awk_parse_number(raw).to_int()
        let mut digits = awk_to_hex_string(num)
        if precision == 0 && num == 0 {
          digits = ""
        }
        if precision > 0 {
          digits = awk_pad_left(digits, precision, '0')
        }
        if spec == 'X' {
          digits = awk_to_upper(digits)
        }
        out.write_string(
          awk_apply_printf_width(digits, width, left_align, zero_pad && precision < 0),
        )
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'f' || spec == 'F' {
        let num = awk_parse_number(raw)
        let text = awk_format_fixed_number(
          num,
          if precision >= 0 { precision } else { 6 },
          plus_sign,
          space_sign,
        )
        out.write_string(awk_apply_printf_width(text, width, left_align, zero_pad && precision < 0))
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'g' || spec == 'G' {
        let num = awk_parse_number(raw)
        let mut text = awk_format_fixed_number(
          num,
          if precision > 0 { precision } else { 6 },
          plus_sign,
          space_sign,
        )
        text = awk_trim_trailing_fraction_zeros(text)
        if spec == 'G' {
          text = awk_to_upper(text)
        }
        out.write_string(awk_apply_printf_width(text, width, left_align, false))
        arg_idx += 1
        i = j + 1
        continue
      }
      out.write_char('%')
      i += 1
      continue
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
  let cond = if cond.length() == 0 { "0" } else { cond }
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

fn awk_strip_optional_braces(s : String) -> String {
  let text = aj_trim(s)
  if text.length() >= 2 &&
    text[0].to_int().unsafe_to_char() == '{' &&
    text[text.length() - 1].to_int().unsafe_to_char() == '}' {
    aj_trim(aj_substr(text, 1, text.length() - 1))
  } else {
    text
  }
}

fn awk_split_if_else_body(body : String) -> (String, String?) {
  let text = aj_trim(body)
  let mut quote : Char? = None
  let mut paren_depth = 0
  let mut brace_depth = 0
  let mut i = 0
  while i + 4 <= text.length() {
    let ch = text[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < text.length() {
          i += 2
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
        } else if ch == '{' {
          brace_depth += 1
        } else if ch == '}' && brace_depth > 0 {
          brace_depth -= 1
        } else if paren_depth == 0 && brace_depth == 0 &&
          aj_substr(text, i, i + 4) == "else" {
          let left_ok = if i == 0 {
            true
          } else {
            awk_is_space(text[i - 1].to_int().unsafe_to_char()) ||
              text[i - 1].to_int().unsafe_to_char() == ';'
          }
          let right_ok = if i + 4 >= text.length() {
            true
          } else {
            let next = text[i + 4].to_int().unsafe_to_char()
            awk_is_space(next) || next == '{'
          }
          if left_ok && right_ok {
            let then_body = awk_strip_optional_braces(aj_substr(text, 0, i))
            let else_body = awk_strip_optional_braces(aj_substr(text, i + 4, text.length()))
            return (then_body, Some(else_body))
          }
        }
      }
    }
    i += 1
  }
  (awk_strip_optional_braces(text), None)
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
    if idx + 1 < text.length() && text[idx + 1].to_int().unsafe_to_char() == '=' {
      return None
    }
    if idx > 0 {
      let prev = text[idx - 1].to_int().unsafe_to_char()
      if prev == '>' || prev == '<' || prev == '=' || prev == '!' {
        return None
      }
    }
    let left = aj_trim(aj_substr(text, 0, idx))
    let right = aj_trim(aj_substr(text, idx + 1, text.length()))
    if right.length() > 0 {
      return Some((left, right, false))
    }
  }
  None
}

fn awk_apply_ofmt_if_needed(expr : String, value : String, vars : Map[String, String]) -> String {
  if not(vars.contains("OFMT")) {
    return value
  }
  if not(awk_is_numeric_string(value)) {
    return value
  }
  let t = aj_trim(expr)
  if (aj_starts_with(t, "\"") && aj_ends_with(t, "\"")) ||
    (aj_starts_with(t, "'") && aj_ends_with(t, "'")) {
    return value
  }
  let fmt = vars.get("OFMT").unwrap_or("%.6g")
  awk_format_printf(fmt, [value])
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
      let value = awk_eval_expr(
        parts[i],
        line,
        fields,
        nr,
        fields.length(),
        vars,
        array_vars,
      )
      out.write_string(awk_apply_ofmt_if_needed(parts[i], value, vars))
    }
  } else {
    let value = awk_eval_expr(
      rest,
      line,
      fields,
      nr,
      fields.length(),
      vars,
      array_vars,
    )
    out.write_string(awk_apply_ofmt_if_needed(rest, value, vars))
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
    return awk_compare_values(left, right, "==")
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
    return awk_compare_values(left, right, "!=")
  }

  idx = awk_find_top_level_token(p, ">=")
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
    return awk_compare_values(left, right, ">=")
  }

  idx = awk_find_top_level_token(p, "<=")
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
    return awk_compare_values(left, right, "<=")
  }

  idx = awk_find_top_level_token(p, ">")
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
      aj_substr(p, idx + 1, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_compare_values(left, right, ">")
  }

  idx = awk_find_top_level_token(p, "<")
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
      aj_substr(p, idx + 1, p.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_compare_values(left, right, "<")
  }

  let value = awk_eval_expr(p, line, fields, nr, nf, vars, array_vars)
  awk_value_truthy(value)
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
  let action = awk_strip_comments(action)
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

fn awk_merge_if_else_statements(statements : Array[String]) -> Array[String] {
  fn is_bare_if_header(stmt : String) -> Bool {
    let text = aj_trim(stmt)
    if not(aj_starts_with(text, "if")) {
      return false
    }
    if text.length() > 2 {
      let boundary = text[2].to_int().unsafe_to_char()
      if not(awk_is_space(boundary)) && boundary != '(' {
        return false
      }
    }
    let mut i = 2
    while i < text.length() && awk_is_space(text[i].to_int().unsafe_to_char()) {
      i += 1
    }
    if i >= text.length() || text[i].to_int().unsafe_to_char() != '(' {
      return false
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
      return false
    }
    let tail = aj_trim(aj_substr(text, j + 1, text.length()))
    tail.length() == 0
  }

  fn is_bare_for_header(stmt : String) -> Bool {
    let text = aj_trim(stmt)
    if not(aj_starts_with(text, "for")) {
      return false
    }
    let mut i = 3
    while i < text.length() && awk_is_space(text[i].to_int().unsafe_to_char()) {
      i += 1
    }
    if i >= text.length() || text[i].to_int().unsafe_to_char() != '(' {
      return false
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
      return false
    }
    let tail = aj_trim(aj_substr(text, j + 1, text.length()))
    tail.length() == 0
  }

  fn statement_has_dangling_control(stmt : String) -> Bool {
    let text = aj_trim(stmt)
    if text.length() == 0 {
      return false
    }
    if is_bare_if_header(text) || is_bare_for_header(text) {
      return true
    }
    match awk_parse_for_statement(text) {
      Some((_init_stmt, _cond_expr, _update_stmt, body_stmt)) =>
        return statement_has_dangling_control(body_stmt)
      None => ()
    }
    match awk_parse_for_in_statement(text) {
      Some((_loop_var, _arr_name, body_stmt)) =>
        return statement_has_dangling_control(body_stmt)
      None => ()
    }
    match awk_parse_if_statement(text) {
      Some((_cond_expr, body_stmt)) => {
        let (then_body, else_body) = awk_split_if_else_body(body_stmt)
        if statement_has_dangling_control(then_body) {
          return true
        }
        match else_body {
          Some(else_stmt) => statement_has_dangling_control(else_stmt)
          None => false
        }
      }
      None => false
    }
  }

  let merged : Array[String] = []
  let mut i = 0
  while i < statements.length() {
    let mut current = aj_trim(statements[i])
    if current.length() == 0 {
      i += 1
      continue
    }
    while i + 1 < statements.length() && statement_has_dangling_control(current) {
      let next_body = aj_trim(statements[i + 1])
      if next_body.length() == 0 {
        i += 1
        continue
      }
      if next_body == "else" || aj_starts_with(next_body, "else ") {
        let can_merge_else = match awk_parse_if_statement(current) {
          Some(_) => true
          None => false
        }
        if can_merge_else {
          current = current + " " + next_body
          i += 1
          continue
        }
        break
      }
      current = current + " " + next_body
      i += 1
    }
    if i + 1 < statements.length() {
      let next = aj_trim(statements[i + 1])
      let can_merge_else = match awk_parse_if_statement(current) {
        Some(_) => true
        None => false
      }
      if (next == "else" || aj_starts_with(next, "else ")) && can_merge_else {
        current = current + " " + next
        i += 1
      }
    }
    merged.push(current)
    i += 1
  }
  merged
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

  let statements = awk_merge_if_else_statements(awk_split_statements(act))
  for stmt_raw in statements {
    if vars.contains(awk_ctrl_exit_key) ||
      vars.contains(awk_ctrl_next_key) ||
      vars.contains(awk_ctrl_return_key) {
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
          if vars.contains(awk_ctrl_exit_key) ||
            vars.contains(awk_ctrl_next_key) ||
            vars.contains(awk_ctrl_return_key) {
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
          if vars.contains(awk_ctrl_exit_key) ||
            vars.contains(awk_ctrl_next_key) ||
            vars.contains(awk_ctrl_return_key) {
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
        let (then_body, else_body) = awk_split_if_else_body(body_stmt)
        let mut cond_passed = false
        let cond_text = awk_strip_outer_parens(cond_expr)
        let gt_idx = awk_find_top_level_token(cond_text, ">")
        let mut handled_getline = false
        if gt_idx > 0 {
          let left_expr = awk_strip_outer_parens(aj_trim(aj_substr(cond_text, 0, gt_idx)))
          let right_expr = aj_trim(aj_substr(cond_text, gt_idx + 1, cond_text.length()))
          if right_expr == "0" && (left_expr == "getline" || aj_starts_with(left_expr, "getline ")) {
            handled_getline = true
            let target = if left_expr.length() > 7 {
              aj_trim(aj_substr(left_expr, 7, left_expr.length()))
            } else {
              ""
            }
            let next_idx = line_idx + consumed + 1
            if next_idx >= 0 && next_idx < lines.length() {
              let next_line = lines[next_idx]
              consumed += 1
              current_nr += 1
              vars["NR"] = current_nr.to_string()
              vars["FNR"] = current_nr.to_string()
              if awk_is_identifier(target) {
                vars[target] = next_line
              } else {
                current_line = next_line
                let current_fs = awk_current_fs(fs, vars)
                current_fields = awk_split_fields(current_line, current_fs)
                vars["NF"] = current_fields.length().to_string()
              }
              cond_passed = true
            } else {
              cond_passed = false
            }
          }
        }
        if not(handled_getline) {
          cond_passed = awk_eval_condition(
            cond_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        }
        if cond_passed {
          let (next_line, next_fields, consumed_if, new_nr) = awk_execute_action(
            ctx,
            then_body,
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
        } else {
          match else_body {
            Some(else_stmt) => {
              let (next_line, next_fields, consumed_if, new_nr) = awk_execute_action(
                ctx,
                else_stmt,
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
            None => ()
          }
        }
        continue
      }
      None => ()
    }

    if stmt == "next" {
      vars[awk_ctrl_next_key] = "1"
      break
    }

    if stmt == "exit" || aj_starts_with(stmt, "exit ") || aj_starts_with(stmt, "exit(") {
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

    if stmt == "return" || aj_starts_with(stmt, "return ") || aj_starts_with(stmt, "return(") {
      let value_expr = if stmt.length() > 6 {
        aj_trim(aj_substr(stmt, 6, stmt.length()))
      } else {
        ""
      }
      let value = if value_expr.length() == 0 {
        ""
      } else {
        awk_eval_expr(
          value_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
      }
      vars[awk_ctrl_return_key] = "1"
      vars[awk_ctrl_return_value_key] = value
      break
    }

    if aj_starts_with(stmt, "system(") && aj_ends_with(stmt, ")") {
      vars[awk_ctrl_error_key] = "system() is not supported"
      vars[awk_ctrl_exit_key] = "1"
      break
    }

    let pipe_getline_idx = awk_find_top_level_token(stmt, "| getline")
    if pipe_getline_idx > 0 {
      let cmd_expr = aj_trim(aj_substr(stmt, 0, pipe_getline_idx))
      let target = aj_trim(aj_substr(stmt, pipe_getline_idx + 9, stmt.length()))
      let command = awk_eval_expr(
        cmd_expr,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      let line_from_cmd = awk_eval_getline_command_line(command)
      if target.length() == 0 {
        current_line = line_from_cmd
        let current_fs = awk_current_fs(fs, vars)
        current_fields = awk_split_fields(current_line, current_fs)
        vars["NF"] = current_fields.length().to_string()
      } else if awk_is_identifier(target) {
        vars[target] = line_from_cmd
      }
      continue
    }

    if stmt == "getline" || aj_starts_with(stmt, "getline ") {
      let tail = if stmt.length() > 7 { aj_trim(aj_substr(stmt, 7, stmt.length())) } else { "" }
      let read_from_file_idx = awk_find_top_level_token(tail, "<")
      if read_from_file_idx > 0 {
        let target = aj_trim(aj_substr(tail, 0, read_from_file_idx))
        let path_expr = aj_trim(aj_substr(tail, read_from_file_idx + 1, tail.length()))
        let path = awk_eval_expr(
          path_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let resolved = try {
          @fs.resolve_path(ctx.cwd, path)
        } catch {
          @fs.FsError(_) => ""
        }
        if resolved.length() > 0 {
          let content = try {
            ctx.fs.read_file(resolved)
          } catch {
            @fs.FsError(_) => ""
          }
          let first_line = aj_first_line(content)
          if target.length() == 0 {
            current_line = first_line
            let current_fs = awk_current_fs(fs, vars)
            current_fields = awk_split_fields(current_line, current_fs)
            vars["NF"] = current_fields.length().to_string()
          } else if awk_is_identifier(target) {
            vars[target] = first_line
          }
        }
        continue
      }
      // Keep parity with current awk-spec skip assumptions:
      // bare getline from BEGIN block stdin is still treated as unsupported.
      if line_idx < 0 && tail.length() == 0 {
        continue
      }

      let next_idx = line_idx + consumed + 1
      if next_idx >= 0 && next_idx < lines.length() {
        consumed += 1
        let next_line = lines[next_idx]
        current_nr += 1
        vars["NR"] = current_nr.to_string()
        vars["FNR"] = current_nr.to_string()
        vars["FILENAME"] = filename
        if tail.length() == 0 {
          current_line = next_line
          let current_fs = awk_current_fs(fs, vars)
          current_fields = awk_split_fields(current_line, current_fs)
          vars["NF"] = current_fields.length().to_string()
        } else if awk_is_identifier(tail) {
          vars[tail] = next_line
        } else {
          current_line = next_line
          let current_fs = awk_current_fs(fs, vars)
          current_fields = awk_split_fields(current_line, current_fs)
          vars["NF"] = current_fields.length().to_string()
        }
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
        let pattern = awk_eval_sub_pattern(
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
      let rest = aj_trim(aj_substr(stmt, 6, stmt.length()))
      let (printf_expr, target_expr, append) = match awk_parse_print_redirection(rest) {
        Some(parsed) => parsed
        None => (rest, "", false)
      }
      let (fmt_expr, arg_exprs) = awk_parse_printf("printf " + printf_expr)
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
      let payload = awk_format_printf(fmt_value, fmt_args)
      if target_expr.length() == 0 {
        out.write_string(payload)
      } else {
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

    match awk_parse_call_expr(stmt) {
      Some((call_name, args)) => {
        if call_name == "close" {
          continue
        }
        if call_name == "sprintf" {
          ignore(
            awk_eval_expr(
              stmt,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            ),
          )
          continue
        }
        match awk_get_function(vars, call_name) {
          Some(_) => {
            ignore(awk_eval_user_function(
              call_name,
              args,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
              out,
            ))
            continue
          }
          None => ()
        }
      }
      None => ()
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
  let normalized_prog_src = awk_strip_comments(prog_src)
  // Guard against parser artifacts where shell fragments are accidentally
  // appended to awk source (e.g. newline followed by `' x=1 ...`).
  if aj_find_substring(normalized_prog_src, "\n'") >= 0 ||
    aj_find_substring(normalized_prog_src, "\r'") >= 0 {
    return @ast.ExecResult::err("awk: syntax error\n")
  }
  let (program_without_functions, functions) = awk_extract_functions(normalized_prog_src)
  let prog = awk_parse_program(program_without_functions)

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
  awk_install_functions(vars, functions)
  for pair in initial_vars {
    vars[pair.0] = pair.1
  }

  for action in prog.begin_actions {
    if vars.contains(awk_ctrl_exit_key) {
      break
    }
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

  let begin_exit = vars.get(awk_ctrl_exit_key)
  match begin_exit {
    Some(_) => vars.remove(awk_ctrl_exit_key)
    None => ()
  }

  if not(vars.contains(awk_ctrl_error_key)) {
    for action in prog.end_actions {
      if vars.contains(awk_ctrl_exit_key) {
        break
      }
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
  }

  if not(vars.contains(awk_ctrl_exit_key)) {
    match begin_exit {
      Some(code) => vars[awk_ctrl_exit_key] = code
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
