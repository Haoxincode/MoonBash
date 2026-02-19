// moon_bash Commands - jq filter rewriting

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

fn jq_prev_non_ws_index(s : String, pos : Int) -> Int {
  let mut i = pos - 1
  while i >= 0 {
    let ch = s[i].to_int().unsafe_to_char()
    if not(jq_is_ws(ch)) {
      return i
    }
    i -= 1
  }
  -1
}

fn jq_next_non_ws_index(s : String, pos : Int) -> Int {
  let mut i = pos
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if not(jq_is_ws(ch)) {
      return i
    }
    i += 1
  }
  -1
}

fn jq_is_plain_ident(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  if not(jq_is_ident_start(text[0].to_int().unsafe_to_char())) {
    return false
  }
  for i = 1; i < text.length(); i = i + 1 {
    if not(jq_is_ident_char(text[i].to_int().unsafe_to_char())) {
      return false
    }
  }
  true
}

fn jq_parse_quoted_ident_at(filter : String, quote_pos : Int) -> (String, Int)? {
  if quote_pos < 0 || quote_pos >= filter.length() {
    return None
  }
  if filter[quote_pos].to_int().unsafe_to_char() != '"' {
    return None
  }
  let ident = StringBuilder::new()
  let mut i = quote_pos + 1
  while i < filter.length() {
    let ch = filter[i].to_int().unsafe_to_char()
    if ch == '\\' {
      return None
    }
    if ch == '"' {
      let name = ident.to_string()
      if jq_is_plain_ident(name) {
        return Some((name, i + 1))
      } else {
        return None
      }
    }
    ident.write_char(ch)
    i += 1
  }
  None
}

fn jq_rewrite_quoted_member_access(filter : String) -> String {
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

        if ch == '.' && i + 1 < filter.length() {
          let next = filter[i + 1].to_int().unsafe_to_char()
          if next == '"' {
            match jq_parse_quoted_ident_at(filter, i + 1) {
              Some((name, end_pos)) => {
                out.write_char('.')
                out.write_string(name)
                i = end_pos
                continue
              }
              None => ()
            }
          } else if next == '[' &&
            i + 2 < filter.length() &&
            filter[i + 2].to_int().unsafe_to_char() == '"' {
            match jq_parse_quoted_ident_at(filter, i + 2) {
              Some((name, end_pos)) => {
                if end_pos < filter.length() &&
                  filter[end_pos].to_int().unsafe_to_char() == ']' {
                  out.write_char('.')
                  out.write_string(name)
                  i = end_pos + 1
                  continue
                }
              }
              None => ()
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

fn jq_is_binary_plus_minus(filter : String, pos : Int) -> Bool {
  if pos < 0 || pos >= filter.length() {
    return false
  }
  let op = filter[pos].to_int().unsafe_to_char()
  if op != '+' && op != '-' {
    return false
  }

  if pos > 1 {
    let prev = filter[pos - 1].to_int().unsafe_to_char()
    let prev_prev = filter[pos - 2].to_int().unsafe_to_char()
    if (prev == 'e' || prev == 'E') &&
      ((prev_prev >= '0' && prev_prev <= '9') || prev_prev == '.') {
      return false
    }
  }

  let prev_idx = jq_prev_non_ws_index(filter, pos)
  if prev_idx < 0 {
    return false
  }
  let prev = filter[prev_idx].to_int().unsafe_to_char()
  if prev == '(' || prev == '[' || prev == '{' || prev == ',' || prev == ':' ||
    prev == '|' || prev == ';' || prev == '+' || prev == '-' || prev == '*' ||
    prev == '/' || prev == '%' || prev == '<' || prev == '>' || prev == '=' ||
    prev == '!' {
    return false
  }

  let next_idx = jq_next_non_ws_index(filter, pos + 1)
  if next_idx < 0 {
    return false
  }
  let next = filter[next_idx].to_int().unsafe_to_char()
  if next == ')' || next == ']' || next == '}' || next == ',' || next == '|' ||
    next == ';' {
    return false
  }
  true
}

fn jq_rewrite_binary_plus_minus(filter : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let mut quote : Char? = None
  let mut last_out : Char? = None

  while i < filter.length() {
    let ch = filter[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        out.write_char(ch)
        last_out = Some(ch)
        if ch == '\\' && i + 1 < filter.length() {
          i += 1
          let escaped = filter[i].to_int().unsafe_to_char()
          out.write_char(escaped)
          last_out = Some(escaped)
        } else if ch == q {
          quote = None
        }
        i += 1
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          out.write_char(ch)
          last_out = Some(ch)
          i += 1
          continue
        }

        if (ch == '+' || ch == '-') &&
          jq_is_binary_plus_minus(filter, i) {
          match last_out {
            Some(last_ch) => if not(jq_is_ws(last_ch)) {
              out.write_char(' ')
              last_out = Some(' ')
            } else {
              ()
            }
            None => ()
          }
          out.write_char(ch)
          last_out = Some(ch)

          let next_idx = jq_next_non_ws_index(filter, i + 1)
          if next_idx >= 0 {
            let next = filter[next_idx].to_int().unsafe_to_char()
            if not(jq_is_ws(next)) {
              out.write_char(' ')
              last_out = Some(' ')
            }
          }
          i += 1
          continue
        }

        out.write_char(ch)
        last_out = Some(ch)
        i += 1
      }
    }
  }
  out.to_string()
}

fn jq_find_matching_paren(filter : String, open_pos : Int) -> Int {
  if open_pos < 0 || open_pos >= filter.length() ||
    filter[open_pos].to_int().unsafe_to_char() != '(' {
    return -1
  }
  let mut i = open_pos + 1
  let mut depth = 1
  let mut quote : Char? = None
  while i < filter.length() {
    let ch = filter[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if ch == '\\' && i + 1 < filter.length() {
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
        } else if ch == '(' {
          depth += 1
        } else if ch == ')' {
          depth -= 1
          if depth == 0 {
            return i
          }
        }
        i += 1
      }
    }
  }
  -1
}

fn jq_split_top_level_semicolon(text : String) -> (String, String)? {
  let mut i = 0
  let mut quote : Char? = None
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  while i < text.length() {
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
        } else if ch == '[' {
          bracket_depth += 1
        } else if ch == ']' && bracket_depth > 0 {
          bracket_depth -= 1
        } else if ch == '{' {
          brace_depth += 1
        } else if ch == '}' && brace_depth > 0 {
          brace_depth -= 1
        } else if ch == ';' &&
          paren_depth == 0 &&
          bracket_depth == 0 &&
          brace_depth == 0 {
          return Some((
            aj_trim(aj_substr(text, 0, i)),
            aj_trim(aj_substr(text, i + 1, text.length())),
          ))
        }
      }
    }
    i += 1
  }
  None
}

fn jq_rewrite_compat_function_calls(filter : String) -> String {
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
        if jq_is_ident_start(ch) {
          let start = i
          i += 1
          while i < filter.length() &&
            jq_is_ident_char(filter[i].to_int().unsafe_to_char()) {
            i += 1
          }
          let ident = aj_substr(filter, start, i)
          let mut next_pos = i
          while next_pos < filter.length() &&
            jq_is_ws(filter[next_pos].to_int().unsafe_to_char()) {
            next_pos += 1
          }
          if next_pos < filter.length() &&
            filter[next_pos].to_int().unsafe_to_char() == '(' {
            let close_pos = jq_find_matching_paren(filter, next_pos)
            if close_pos > next_pos {
              let call_args = aj_substr(filter, next_pos + 1, close_pos)
              if ident == "error" {
                out.write_string("error")
                i = close_pos + 1
                continue
              }
              if ident == "isempty" {
                out.write_string("([\{call_args}]|length==0)")
                i = close_pos + 1
                continue
              }
              if ident == "first" {
                out.write_string("([\{call_args}]|.[0])")
                i = close_pos + 1
                continue
              }
              if ident == "last" {
                out.write_string("([\{call_args}]|.[-1])")
                i = close_pos + 1
                continue
              }
              if ident == "skip" {
                match jq_split_top_level_semicolon(call_args) {
                  Some((count_expr, value_expr)) => {
                    out.write_string("([\{value_expr}]|.[\{count_expr}:]|.[])")
                    i = close_pos + 1
                    continue
                  }
                  None => ()
                }
              }
              if ident == "nth" {
                match jq_split_top_level_semicolon(call_args) {
                  Some((idx_expr, value_expr)) => {
                    out.write_string("([\{value_expr}]|.[\{idx_expr}])")
                    i = close_pos + 1
                    continue
                  }
                  None => ()
                }
              }
              if ident == "limit" {
                match jq_split_top_level_semicolon(call_args) {
                  Some((count_expr, value_expr)) => {
                    out.write_string("([\{value_expr}]|.[:\{count_expr}]|.[])")
                    i = close_pos + 1
                    continue
                  }
                  None => ()
                }
              }
            }
          }
          out.write_string(ident)
          continue
        }
        out.write_char(ch)
        i += 1
      }
    }
  }
  out.to_string()
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

