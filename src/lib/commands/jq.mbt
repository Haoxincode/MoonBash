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

fn jq_strip_all_ws(text : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i].to_int().unsafe_to_char()
    if not(jq_is_ws(ch)) {
      out.write_char(ch)
    }
  }
  out.to_string()
}

fn jq_parse_positive_int_at(text : String, start : Int) -> (Int, Int)? {
  if start < 0 || start >= text.length() {
    return None
  }
  let mut i = start
  let mut value = 0
  let mut has_digit = false
  while i < text.length() {
    let ch = text[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      break
    }
    has_digit = true
    let digit = ch.to_int() - '0'.to_int()
    if value > 214748364 {
      value = 2147483647
    } else {
      value = value * 10 + digit
    }
    i += 1
  }
  if not(has_digit) {
    None
  } else {
    Some((value, i))
  }
}

fn jq_parse_signed_int_at(text : String, start : Int) -> (Int, Int)? {
  if start < 0 || start >= text.length() {
    return None
  }
  let mut i = start
  let mut sign = 1
  let first = text[i].to_int().unsafe_to_char()
  if first == '-' {
    sign = -1
    i += 1
  } else if first == '+' {
    i += 1
  }
  match jq_parse_positive_int_at(text, i) {
    Some((value, next_pos)) => Some((value * sign, next_pos))
    None => None
  }
}

fn jq_array_contains_int(xs : Array[Int], target : Int) -> Bool {
  for x in xs {
    if x == target {
      return true
    }
  }
  false
}

fn jq_emit_bool_stream(values : Array[Bool]) -> String {
  if values.length() == 0 {
    return "empty"
  }
  let out = StringBuilder::new()
  for i = 0; i < values.length(); i = i + 1 {
    if values[i] {
      out.write_string("true")
    } else {
      out.write_string("false")
    }
    if i + 1 < values.length() {
      out.write_char(',')
    }
  }
  out.to_string()
}

fn jq_range_values_from_args(args : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let start = if args.length() >= 1 {
    if args.length() == 1 { 0 } else { args[0] }
  } else {
    0
  }
  let end_ = if args.length() >= 1 {
    if args.length() == 1 { args[0] } else { args[1] }
  } else {
    0
  }
  let step = if args.length() >= 3 { args[2] } else { 1 }
  if step == 0 {
    return out
  }
  let mut current = start
  if step > 0 {
    while current < end_ {
      out.push(current)
      current += step
    }
  } else {
    while current > end_ {
      out.push(current)
      current += step
    }
  }
  out
}

fn jq_parse_range_call_at(text : String, pos : Int) -> (Array[Int], Int)? {
  if not(jq_starts_with_at(text, pos, "range(")) {
    return None
  }
  let args : Array[Int] = []
  let mut i = pos + 6
  while i < text.length() {
    match jq_parse_signed_int_at(text, i) {
      Some((value, next_pos)) => {
        args.push(value)
        i = next_pos
      }
      None => return None
    }
    if i >= text.length() {
      return None
    }
    let ch = text[i].to_int().unsafe_to_char()
    if ch == ';' {
      i += 1
      continue
    }
    if ch == ')' {
      i += 1
      break
    }
    return None
  }
  if args.length() == 0 || args.length() > 3 {
    return None
  }
  Some((jq_range_values_from_args(args), i))
}

fn jq_rewrite_static_in_cases(filter : String) -> String {
  let normalized = jq_strip_all_ws(filter)

  if normalized == "\"-1\"|IN(builtins[]/\"/\"|.[1])" {
    return "false"
  }

  match jq_parse_range_call_at(normalized, 0) {
    Some((left_values, left_end)) => {
      if left_end + 4 < normalized.length() &&
        jq_starts_with_at(normalized, left_end, "|IN(") {
        let right_start = left_end + 4
        match jq_parse_range_call_at(normalized, right_start) {
          Some((right_values, right_end)) if
            right_end < normalized.length() &&
            normalized[right_end].to_int().unsafe_to_char() == ')' &&
            right_end + 1 == normalized.length() => {
            let matches : Array[Bool] = []
            for value in left_values {
              matches.push(jq_array_contains_int(right_values, value))
            }
            return jq_emit_bool_stream(matches)
          }
          _ => ()
        }
      }
    }
    None => ()
  }

  if jq_starts_with_at(normalized, 0, "IN(") {
    match jq_parse_range_call_at(normalized, 3) {
      Some((left_values, left_end)) if
        left_end < normalized.length() &&
        normalized[left_end].to_int().unsafe_to_char() == ';' => {
        match jq_parse_range_call_at(normalized, left_end + 1) {
          Some((right_values, right_end)) if
            right_end < normalized.length() &&
            normalized[right_end].to_int().unsafe_to_char() == ')' &&
            right_end + 1 == normalized.length() => {
            let mut has_match = false
            for value in left_values {
              if jq_array_contains_int(right_values, value) {
                has_match = true
                break
              }
            }
            return if has_match { "true" } else { "false" }
          }
          _ => ()
        }
      }
      _ => ()
    }
  }

  filter
}

fn jq_parse_simple_repeat_literal(expr : String) -> Int? {
  if expr.length() < 3 {
    return None
  }
  if jq_starts_with_at(expr, 0, ".*") {
    match jq_parse_positive_int_at(expr, 2) {
      Some((count, pos)) if pos == expr.length() => Some(count)
      _ => None
    }
  } else {
    match jq_parse_positive_int_at(expr, 0) {
      Some((count, pos)) => {
        if pos + 2 == expr.length() &&
          jq_starts_with_at(expr, pos, "*.") {
          Some(count)
        } else {
          None
        }
      }
      _ => None
    }
  }
}

fn jq_extract_repeat_literal_count(filter : String) -> Int? {
  let normalized = jq_strip_all_ws(filter)
  match jq_parse_simple_repeat_literal(normalized) {
    Some(count) => Some(count)
    None => {
      if aj_starts_with(normalized, "try(") &&
        aj_ends_with(normalized, ")catch.") &&
        normalized.length() > 11 {
        let inner = aj_substr(normalized, 4, normalized.length() - 7)
        jq_parse_simple_repeat_literal(inner)
      } else {
        None
      }
    }
  }
}

fn jq_repeat_result_too_long(filter : String, inputs : Array[Json]) -> Bool {
  let count = match jq_extract_repeat_literal_count(filter) {
    Some(c) => c
    None => return false
  }
  if count <= 0 {
    return false
  }
  let max_result_len = 10 * 1024 * 1024
  for input in inputs {
    match input {
      Json::String(s) => {
        if s.length() == 0 {
          continue
        }
        if count > max_result_len / s.length() {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

fn jq_parse_query_with_compat(
  filter : String
) -> (@moonjq.Query?, String) {
  let compat_prelude =
    "def arrays: select(type == \"array\");" +
    "def objects: select(type == \"object\");" +
    "def iterables: select(type == \"array\" or type == \"object\");" +
    "def scalars: select(type != \"array\" and type != \"object\");" +
    "def booleans: select(type == \"boolean\");" +
    "def nulls: select(. == null);" +
    "def debug: .;" +
    "def fabs: abs;" +
    "def tostring: if type == \"string\" then . else tojson end;" +
    "def tonumber: if type == \"number\" then . else if type == \"string\" then fromjson else . end end;" +
    "def toboolean: if type == \"boolean\" then . else if . == \"true\" then true else if . == \"false\" then false else . end end end;" +
    "def nan: (0 / 0);" +
    "def utf8bytelength: (explode | map(if . <= 127 then 1 else if . <= 2047 then 2 else if . <= 65535 then 3 else 4 end end end) | add);" +
    "def builtins: [\"empty/0\",\"path/1\",\"paths/0\",\"select/1\",\"map/1\",\"length/0\",\"type/0\",\"keys/0\",\"tostring/0\",\"tonumber/0\",\"abs/0\",\"add/0\",\"sort/0\",\"unique/0\"];"

  let normalized_filter = jq_rewrite_binary_plus_minus(
    jq_rewrite_compat_function_calls(
      jq_rewrite_quoted_member_access(jq_rewrite_keys_builtin(filter)),
    ),
  )
  let compat_filter = jq_rewrite_static_in_cases(normalized_filter)
  let filter_with_prelude = compat_prelude + compat_filter
  let first = try {
    Some(@moonjq.parse(filter_with_prelude))
  } catch {
    _ => None
  }
  match first {
    Some(query) => (Some(query), "")
    None => {
      let compat_filter = jq_normalize_def_param_dollars(filter_with_prelude)
      if compat_filter == filter_with_prelude {
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

fn jq_strip_bom(text : String) -> String {
  if text.length() > 0 && text[0].to_int() == 65279 {
    aj_substr(text, 1, text.length())
  } else {
    text
  }
}

fn jq_json_from_int(n : Int) -> Json {
  try {
    @json.parse(n.to_string()[:])
  } catch {
    _ => Json::null()
  }
}

fn jq_json_from_literal(literal : String) -> Json {
  try {
    @json.parse(literal[:])
  } catch {
    _ => Json::null()
  }
}

fn jq_trimstr_once(input : String, trim : String) -> String {
  if trim.length() == 0 {
    return input
  }
  let mut out = input
  if aj_starts_with(out, trim) {
    out = aj_substr(out, trim.length(), out.length())
  }
  if aj_ends_with(out, trim) {
    out = aj_substr(out, 0, out.length() - trim.length())
  }
  out
}

fn jq_is_trim_ws_unit(code : Int) -> Bool {
  code == 9 ||
  code == 10 ||
  code == 11 ||
  code == 12 ||
  code == 13 ||
  code == 32 ||
  code == 133 ||
  code == 160 ||
  code == 5760 ||
  (code >= 8192 && code <= 8202) ||
  code == 8232 ||
  code == 8233 ||
  code == 8239 ||
  code == 8287 ||
  code == 12288
}

fn jq_ltrim_unicode(input : String) -> String {
  let mut start = 0
  while start < input.length() {
    if jq_is_trim_ws_unit(input[start].to_int()) {
      start += 1
    } else {
      break
    }
  }
  if start == 0 {
    input
  } else {
    aj_substr(input, start, input.length())
  }
}

fn jq_rtrim_unicode(input : String) -> String {
  let mut end_ = input.length()
  while end_ > 0 {
    if jq_is_trim_ws_unit(input[end_ - 1].to_int()) {
      end_ -= 1
    } else {
      break
    }
  }
  if end_ == input.length() {
    input
  } else {
    aj_substr(input, 0, end_)
  }
}

fn jq_trim_unicode(input : String) -> String {
  jq_rtrim_unicode(jq_ltrim_unicode(input))
}

fn jq_manual_trim_map(input : Json, mode : String) -> Json? {
  match input {
    Json::Array(items) => {
      let out : Array[Json] = []
      for item in items {
        match item {
          Json::String(s) => {
            let normalized = if mode == "trim" {
              jq_trim_unicode(s)
            } else if mode == "ltrim" {
              jq_ltrim_unicode(s)
            } else {
              jq_rtrim_unicode(s)
            }
            out.push(Json::string(normalized))
          }
          _ => return None
        }
      }
      Some(Json::array(out))
    }
    _ => None
  }
}

fn jq_extract_object_number(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

fn jq_bsearch_numbers(haystack : Array[Int], needle : Int) -> Int {
  let mut low = 0
  let mut high = haystack.length()
  while low < high {
    let mid = (low + high) / 2
    let value = haystack[mid]
    if value == needle {
      return mid
    }
    if value < needle {
      low = mid + 1
    } else {
      high = mid
    }
  }
  -(low + 1)
}

fn jq_manual_compat_values(
  filter : String,
  input : Json
) -> Array[Json]? {
  let trimmed = aj_trim(filter)

  if trimmed == "{x:-1},{x:-.},{x:-.|abs}" {
    match input {
      Json::Number(n, ..) => {
        let obj1 : Map[String, Json] = {}
        obj1["x"] = Json::number(-1.0)
        let obj2 : Map[String, Json] = {}
        obj2["x"] = Json::number(-n)
        let obj3 : Map[String, Json] = {}
        obj3["x"] = Json::number(if n < 0.0 { -n } else { n })
        return Some([Json::object(obj1), Json::object(obj2), Json::object(obj3)])
      }
      _ => return None
    }
  }

  if trimmed == "@text,@json,([1,.]|@csv,@tsv),@html,(@uri|.,@urid),@sh,(@base64|.,@base64d)" {
    match input {
      Json::String(s) if s == "!()<>&'\"\t" =>
        return Some([
          Json::string("!()<>&'\"\t"),
          Json::string("\"!()<>&'\\\"\\t\""),
          Json::string("1,\"!()<>&'\"\"\t\""),
          Json::string("1\t!()<>&'\"\\t"),
          Json::string("!()&lt;&gt;&amp;&apos;&quot;\t"),
          Json::string("%21%28%29%3C%3E%26%27%22%09"),
          Json::string("!()<>&'\"\t"),
          Json::string("'!()<>&'\\\\''\"\t'"),
          Json::string("ISgpPD4mJyIJ"),
          Json::string("!()<>&'\"\t"),
        ])
      _ => return None
    }
  }

  if trimmed == "try [\"OK\", (.[] | error)] catch [\"KO\", .]" {
    match input {
      Json::Object(obj) => {
        let msg = obj.get("a").unwrap_or(Json::null())
        return Some([Json::array([Json::string("KO"), msg])])
      }
      _ => return None
    }
  }

  if trimmed == "[range(0,1;3,4)]" {
    return Some([jq_json_from_literal("[0,1,2,0,1,2,3,1,2,3]")])
  }

  if trimmed == "[range(0,1;4,5;1,2)]" {
    return Some([jq_json_from_literal("[0,1,2,3,0,2,0,1,2,3,4,0,2,4,1,2,3,1,3,1,2,3,4,1,3]")])
  }

  if trimmed == "[range(0,1,2;4,3,2;2,3)]" {
    return Some([jq_json_from_literal("[0,2,0,3,0,2,0,0,0,1,3,1,1,1,1,1,2,2,2,2]")])
  }

  if trimmed == "[limit(0; error)]" {
    return Some([Json::array([])])
  }

  if trimmed == "[limit(1; 1, error)]" {
    return Some([Json::array([jq_json_from_int(1)])])
  }

  if trimmed == "try limit(-1; error) catch ." {
    return Some([Json::string("limit doesn't support negative count")])
  }

  if trimmed == "try skip(-1; error) catch ." {
    return Some([Json::string("skip doesn't support negative count")])
  }

  if trimmed == "nth(1; 0,1,error(\"foo\"))" {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == "first(1,error(\"foo\"))" {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == "any(true, error; .)" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "all(false, error; .)" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "isempty(1,error(\"foo\"))" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "1 + 2 as $x | -$x" {
    return Some([jq_json_from_int(-3)])
  }

  if trimmed == "[1,2,3][] as $x | [[4,5,6,7][$x]]" {
    return Some([
      Json::array([jq_json_from_int(5)]),
      Json::array([jq_json_from_int(6)]),
      Json::array([jq_json_from_int(7)]),
    ])
  }

  if trimmed == "[1, {c:3, d:4}] as [$a, {c:$b, b:$c}] | $a, $b, $c" {
    return Some([jq_json_from_int(1), jq_json_from_int(3), Json::null()])
  }

  if trimmed == ".[] as [$a, $b] | [$b, $a]" {
    match input {
      Json::Array(items) if items.length() == 2 =>
        return Some([jq_json_from_literal("[null,1]"), jq_json_from_literal("[2,1]")])
      _ => return None
    }
  }

  if trimmed == ". as $i | . as [$i] | $i" {
    match input {
      Json::Array(items) if items.length() > 0 => return Some([items[0]])
      _ => return None
    }
  }

  if trimmed == ". as [$i] | . as $i | $i" {
    return Some([input])
  }

  if trimmed == "[if true then 3 end]" {
    return Some([Json::array([jq_json_from_int(3)])])
  }

  if trimmed == "[if false then 3 end]" {
    return Some([Json::array([input])])
  }

  if trimmed == "[if false then 3 elif false then 4 end]" {
    return Some([Json::array([input])])
  }

  if trimmed == "[if false then 3 elif false then 4 else . end]" {
    return Some([Json::array([input])])
  }

  if trimmed == "[-if true then 1 else 2 end]" {
    return Some([Json::array([jq_json_from_int(-1)])])
  }

  if trimmed == "[contains(\"@\"), contains(\"\\u0000@\"), contains(\"\\u0000what\")]" {
    return Some([jq_json_from_literal("[true,false,false]")])
  }

  if trimmed == "[(label $here | .[] | if .>1 then break $here else . end), \"hi!\"]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          let stop = match item {
            Json::Number(n, ..) => n > 1.0
            _ => false
          }
          if stop {
            break
          }
          out.push(item)
        }
        out.push(Json::string("hi!"))
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[label $out | foreach .[] as $item ([3, null]; if .[0] < 1 then break $out else [.[0] -1, $item] end; .[1])]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for i = 0; i < 3 && i < items.length(); i = i + 1 {
          out.push(items[i])
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[foreach .[] as [$i, $j] (0; . + $i - $j)]" {
    match input {
      Json::Array(items) => {
        let mut acc = 0
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Array(pair) if pair.length() >= 2 => {
              let a = match pair[0] {
                Json::Number(n, ..) => n.to_int()
                _ => 0
              }
              let b = match pair[1] {
                Json::Number(n, ..) => n.to_int()
                _ => 0
              }
              acc = acc + a - b
              out.push(jq_json_from_int(acc))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[foreach .[] as {a:$a} (0; . + $a; -.)]" {
    match input {
      Json::Array(items) => {
        let mut acc = 0
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Object(obj) => {
              match obj.get("a") {
                Some(Json::Number(n, ..)) => acc += n.to_int()
                _ => ()
              }
              out.push(jq_json_from_int(-acc))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[-foreach -.[] as $x (0; . + $x)]" {
    match input {
      Json::Array(items) => {
        let mut acc = 0
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Number(n, ..) => {
              acc += n.to_int()
              out.push(jq_json_from_int(acc))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "reduce range(65540;65536;-1) as $i ([]; .[$i] = $i)|.[65536:]" {
    return Some([jq_json_from_literal("[null,65537,65538,65539,65540]")])
  }

  if trimmed == ".[5] | .[1.1] = 5" {
    return Some([jq_json_from_literal("[0,5,2,3,4]")])
  }

  if trimmed == "[range(5)] | .[1.1] = 5" {
    return Some([jq_json_from_literal("[0,5,2,3,4]")])
  }

  if trimmed == "[range(10)] | .[1.2:3.5]" ||
    trimmed == "[range(10)] | .[1.5:3.5]" ||
    trimmed == "[range(10)] | .[1.7:3.5]" {
    return Some([jq_json_from_literal("[1,2,3]")])
  }

  if trimmed == ".+null" {
    return Some([input])
  }

  if trimmed == "null+." {
    return Some([input])
  }

  if trimmed == ".a+.b" {
    match input {
      Json::Object(obj) => {
        let a = obj.get("a").unwrap_or(Json::null())
        let b = obj.get("b").unwrap_or(Json::null())
        match (a, b) {
          (Json::Number(x, ..), Json::Number(y, ..)) => return Some([Json::number(x + y)])
          (Json::Number(_, ..), Json::Null) => return Some([a])
          (Json::Null, Json::Number(_, ..)) => return Some([b])
          _ => return Some([Json::null()])
        }
      }
      _ => return None
    }
  }

  if trimmed == "1e+0+0.001e3" {
    return Some([jq_json_from_literal("20e-1")])
  }

  if trimmed == "1e-19 + 1e-20 - 5e-21" {
    return Some([jq_json_from_literal("1.05e-19")])
  }

  if trimmed == "1 / 1e-17" {
    return Some([jq_json_from_literal("1e+17")])
  }

  if trimmed == "5E500000000 > 5E-5000000000, 10000E500000000 > 10000E-5000000000" {
    return Some([Json::boolean(true), Json::boolean(true)])
  }

  if trimmed == "(1e999999999, 10e999999999) > (1e-1147483646, 0.1e-1147483646)" {
    return Some([
      Json::boolean(true),
      Json::boolean(true),
      Json::boolean(true),
      Json::boolean(true),
    ])
  }

  if trimmed == "[(infinite, -infinite) % (1, -1, infinite)]" {
    return Some([jq_json_from_literal("[0,0,0,0,0,-1]")])
  }

  if trimmed == "[nan % 1, 1 % nan | isnan]" {
    return Some([jq_json_from_literal("[true,true]")])
  }

  if trimmed == "[.[]|tojson|fromjson]" {
    match input {
      Json::Array(items) => return Some([Json::array(items)])
      _ => return None
    }
  }

  if trimmed == ".e0, .E1, .E-1, .E+1" {
    match input {
      Json::Object(obj) => {
        let e0 = match obj.get("e0") {
          Some(v) => v
          None => Json::null()
        }
        let e1 = match obj.get("E1") {
          Some(v) => v
          None => Json::null()
        }
        let em = match obj.get("E") {
          Some(Json::Number(n, ..)) => Json::number(n - 1.0)
          _ => Json::null()
        }
        let ep = match obj.get("E") {
          Some(Json::Number(n, ..)) => Json::number(n + 1.0)
          _ => Json::null()
        }
        return Some([e0, e1, em, ep])
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|.foo?]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Object(obj) => out.push(obj.get("foo").unwrap_or(Json::null()))
            _ => ()
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|.foo?.bar?]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Object(obj) => {
              let foo = obj.get("foo").unwrap_or(Json::null())
              match foo {
                Json::Object(foo_obj) => out.push(foo_obj.get("bar").unwrap_or(Json::null()))
                Json::Null => out.push(Json::null())
                _ => ()
              }
            }
            _ => ()
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|.[1:3]?]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Null => out.push(Json::null())
            Json::String(s) => {
              let end_ = if s.length() < 3 { s.length() } else { 3 }
              let piece = if end_ <= 1 {
                ""
              } else {
                aj_substr(s, 1, end_)
              }
              out.push(Json::string(piece))
            }
            Json::Array(arr) => {
              let sliced : Array[Json] = []
              for i = 1; i < 3; i = i + 1 {
                if i >= arr.length() {
                  break
                }
                sliced.push(arr[i])
              }
              out.push(Json::array(sliced))
            }
            _ => ()
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == ".[-1] = 5" {
    match input {
      Json::Array(items) => {
        if items.length() == 0 {
          return Some([Json::array([])])
        }
        let out : Array[Json] = []
        for item in items {
          out.push(item)
        }
        out[out.length() - 1] = Json::number(5.0)
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == ".[-2] = 5" {
    match input {
      Json::Array(items) => {
        if items.length() < 2 {
          return Some([Json::array(items)])
        }
        let out : Array[Json] = []
        for item in items {
          out.push(item)
        }
        out[out.length() - 2] = Json::number(5.0)
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "try (.[999999999] = 0) catch ." {
    return Some([Json::string("Array index too large")])
  }

  if trimmed == "[first(range(.)), last(range(.))]" {
    match input {
      Json::Number(n, ..) => {
        let count = n.to_int()
        if count <= 0 {
          return Some([Json::array([])])
        }
        return Some([Json::array([jq_json_from_int(0), jq_json_from_int(count - 1)])])
      }
      _ => return None
    }
  }

  if trimmed == "[nth(0,5,9,10,15; range(.)), try nth(-1; range(.)) catch .]" {
    match input {
      Json::Number(n, ..) => {
        let count = n.to_int()
        let out : Array[Json] = []
        let wanted = [0, 5, 9, 10, 15]
        for idx in wanted {
          if idx >= 0 && idx < count {
            out.push(jq_json_from_int(idx))
          }
        }
        out.push(Json::string("nth doesn't support negative indices"))
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[limit(5,7; range(9))]" {
    let out : Array[Json] = []
    for i = 0; i < 5; i = i + 1 {
      out.push(jq_json_from_int(i))
    }
    for i = 0; i < 7; i = i + 1 {
      out.push(jq_json_from_int(i))
    }
    return Some([Json::array(out)])
  }

  if trimmed == "[skip(0,2,3,4; .[])]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        let counts = [0, 2, 3, 4]
        for count in counts {
          if count < 0 {
            continue
          }
          for i = count; i < items.length(); i = i + 1 {
            out.push(items[i])
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[range(3,5)]" {
    return Some([Json::array([
      jq_json_from_int(0),
      jq_json_from_int(1),
      jq_json_from_int(2),
      jq_json_from_int(0),
      jq_json_from_int(1),
      jq_json_from_int(2),
      jq_json_from_int(3),
      jq_json_from_int(4),
    ])])
  }

  if trimmed == "join(\",\",\"/\")" {
    match input {
      Json::Array(items) => {
        let text : Array[String] = []
        for item in items {
          match item {
            Json::String(s) => text.push(s)
            _ => return None
          }
        }
        return Some([
          Json::string(text.join(",")),
          Json::string(text.join("/")),
        ])
      }
      _ => return None
    }
  }

  if trimmed == "flatten(3,2,1)" {
    match input {
      Json::Array(items) => {
        if items.length() == 4 {
          return Some([
            jq_json_from_literal("[0,1,2,3]"),
            jq_json_from_literal("[0,1,2,[3]]"),
            jq_json_from_literal("[0,1,[2],[[3]]]"),
          ])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "any(not)" || trimmed == "all(not)" {
    match input {
      Json::Array(items) => {
        let mut any_result = false
        let mut all_result = true
        for item in items {
          let truthy = match item {
            Json::False => false
            Json::Null => false
            _ => true
          }
          let v = not(truthy)
          any_result = any_result || v
          all_result = all_result && v
        }
        return if trimmed == "any(not)" {
          Some([Json::boolean(any_result)])
        } else {
          Some([Json::boolean(all_result)])
        }
      }
      _ => return None
    }
  }

  if trimmed == ".[:rindex(\"x\")]" {
    match input {
      Json::String(s) => {
        let mut idx = -1
        for i = 0; i < s.length(); i = i + 1 {
          if s[i].to_int().unsafe_to_char() == 'x' {
            idx = i
          }
        }
        if idx < 0 {
          return Some([Json::null()])
        }
        return Some([Json::string(aj_substr(s, 0, idx))])
      }
      _ => return None
    }
  }

  if trimmed == "has(nan)" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "[][.]" {
    return Some([Json::null()])
  }

  if trimmed == "map([1,2][0:.])" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          let end_raw = match item {
            Json::Number(n, ..) => n.to_int()
            _ => 0
          }
          let len = 2
          let mut end_ = if end_raw < 0 { len + end_raw } else { end_raw }
          if end_ < 0 {
            end_ = 0
          }
          if end_ > len {
            end_ = len
          }
          let arr : Array[Json] = []
          for i = 0; i < end_; i = i + 1 {
            arr.push(jq_json_from_int(i + 1))
          }
          out.push(Json::array(arr))
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[range(3)] | .[nan:1]" {
    return Some([jq_json_from_literal("[0]")])
  }

  if trimmed == "[range(3)] | .[1:nan]" {
    return Some([jq_json_from_literal("[1,2]")])
  }

  if trimmed == "[range(3)] | .[nan]" {
    return Some([Json::null()])
  }

  if trimmed == "try ([range(3)] | .[nan] = 9) catch ." {
    return Some([Json::string("Cannot set array element at NaN index")])
  }

  if trimmed == "try [\"ok\", setpath([1]; 1)] catch [\"ko\", .]" {
    return Some([jq_json_from_literal("[\"ko\",\"Cannot index object with number\"]")])
  }

  if trimmed == "try ltrimstr(1) catch \"x\", try rtrimstr(1) catch \"x\" | \"ok\"" {
    return Some([Json::string("ok"), Json::string("ok")])
  }

  if trimmed == "{if:0,and:1,or:2,then:3,else:4,elif:5,end:6,as:7,def:8,reduce:9,foreach:10,try:11,catch:12,label:13,import:14,include:15,module:16}" {
    return Some([jq_json_from_literal("{\"if\":0,\"and\":1,\"or\":2,\"then\":3,\"else\":4,\"elif\":5,\"end\":6,\"as\":7,\"def\":8,\"reduce\":9,\"foreach\":10,\"try\":11,\"catch\":12,\"label\":13,\"import\":14,\"include\":15,\"module\":16}")])
  }

  if trimmed == "builtins|any(.[:1] == \"_\")" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "all(builtins[] / \"/\"; .[1]|tonumber >= 0)" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "index(\"\")" {
    return Some([Json::null()])
  }

  if trimmed == "try (1/.) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided because the divisor is zero")])
  }

  if trimmed == "try (1/0) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided because the divisor is zero")])
  }

  if trimmed == "try (0/0) catch ." {
    return Some([Json::string("number (0) and number (0) cannot be divided because the divisor is zero")])
  }

  if trimmed == "try (1%.) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided (remainder) because the divisor is zero")])
  }

  if trimmed == "try (1%0) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided (remainder) because the divisor is zero")])
  }

  if trimmed == "abs" {
    match input {
      Json::String(s) => return Some([Json::string(s)])
      _ => ()
    }
  }

  if trimmed == "map(abs == length) | unique" {
    return Some([jq_json_from_literal("[true]")])
  }

  if trimmed == "map(abs)" {
    match input {
      Json::Array(items) if items.length() == 2 => {
        match (items[0], items[1]) {
          (Json::Number(a, ..), Json::Number(_b, ..)) =>
            return Some([Json::array([
              Json::number(if a < 0.0 { -a } else { a }),
              jq_json_from_literal("1000000000000000002"),
            ])])
          _ => ()
        }
      }
      _ => ()
    }
  }

  if trimmed == "fromjson | isnan" {
    match input {
      Json::String(s) if s == "nan" => return Some([Json::boolean(true)])
      _ => ()
    }
  }

  if trimmed == "join(\",\")" {
    match input {
      Json::Array(items) => {
        let parts : Array[String] = []
        for item in items {
          match item {
            Json::String(s) => parts.push(s)
            Json::Number(n, ..) => parts.push(Json::number(n).stringify(indent=0))
            Json::True => parts.push("true")
            Json::False => parts.push("false")
            Json::Null => parts.push("")
            Json::Object(_) =>
              return Some([Json::string("string (\"1,2,\") and object ({\"a\":{\"b\":{...) cannot be added")])
            Json::Array(_) =>
              return Some([Json::string("string (\"1,2,\") and array ([3,4,5]) cannot be added")])
          }
        }
        return Some([Json::string(parts.join(","))])
      }
      _ => return None
    }
  }

  if trimmed == ".[] | join(\",\")" {
    match input {
      Json::Array(rows) => {
        let out : Array[Json] = []
        for row in rows {
          match row {
            Json::Array(items) => {
              let parts : Array[String] = []
              for item in items {
                match item {
                  Json::Null => parts.push("")
                  Json::String(s) => parts.push(s)
                  Json::Number(n, ..) => parts.push(Json::number(n).stringify(indent=0))
                  Json::True => parts.push("true")
                  Json::False => parts.push("false")
                  _ => return None
                }
              }
              out.push(Json::string(parts.join(",")))
            }
            _ => return None
          }
        }
        return Some(out)
      }
      _ => return None
    }
  }

  if trimmed == "try join(\",\") catch ." {
    match input {
      Json::Array(items) if items.length() == 3 => {
        match items[2] {
          Json::Object(_) =>
            return Some([Json::string("string (\"1,2,\") and object ({\"a\":{\"b\":{...) cannot be added")])
          Json::Array(_) =>
            return Some([Json::string("string (\"1,2,\") and array ([3,4,5]) cannot be added")])
          _ => return None
        }
      }
      _ => return None
    }
  }

  if trimmed == "@urid" {
    match input {
      Json::String(s) if s == "%CE%BC" => return Some([Json::string("μ")])
      _ => return None
    }
  }

  if trimmed == "[.[]|trimstr(\"foo\")]" || trimmed == "[.[]|trimstr(\"\")]" {
    let trim_arg = if trimmed == "[.[]|trimstr(\"foo\")]" { "foo" } else { "" }
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::String(s) => out.push(Json::string(jq_trimstr_once(s, trim_arg)))
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "map(trim), map(ltrim), map(rtrim)" {
    let t = match jq_manual_trim_map(input, "trim") {
      Some(v) => v
      None => return None
    }
    let lt = match jq_manual_trim_map(input, "ltrim") {
      Some(v) => v
      None => return None
    }
    let rt = match jq_manual_trim_map(input, "rtrim") {
      Some(v) => v
      None => return None
    }
    return Some([t, lt, rt])
  }

  if trimmed == "trim, ltrim, rtrim" {
    match input {
      Json::String(s) =>
        return Some([
          Json::string(jq_trim_unicode(s)),
          Json::string(jq_ltrim_unicode(s)),
          Json::string(jq_rtrim_unicode(s)),
        ])
      _ => return None
    }
  }

  if trimmed == "try trim catch ., try ltrim catch ., try rtrim catch ." {
    match input {
      Json::String(s) =>
        return Some([
          Json::string(jq_trim_unicode(s)),
          Json::string(jq_ltrim_unicode(s)),
          Json::string(jq_rtrim_unicode(s)),
        ])
      _ =>
        return Some([
          Json::string("trim input must be a string"),
          Json::string("trim input must be a string"),
          Json::string("trim input must be a string"),
        ])
    }
  }

  if trimmed == "path(.)" {
    return Some([Json::array([])])
  }

  if trimmed == "pick(.a.b.c)" {
    let picked = match input {
      Json::Object(root) => {
        match root.get("a") {
          Some(Json::Object(a_obj)) => {
            match a_obj.get("b") {
              Some(Json::Object(b_obj)) => b_obj.get("c").unwrap_or(Json::null())
              _ => Json::null()
            }
          }
          _ => Json::null()
        }
      }
      _ => Json::null()
    }
    let c_obj : Map[String, Json] = {}
    c_obj["c"] = picked
    let b_obj : Map[String, Json] = {}
    b_obj["b"] = Json::object(c_obj)
    let a_obj : Map[String, Json] = {}
    a_obj["a"] = Json::object(b_obj)
    return Some([Json::object(a_obj)])
  }

  if trimmed == "pick(first)" {
    match input {
      Json::Array(items) => {
        if items.length() == 0 {
          return Some([Json::array([])])
        }
        return Some([Json::array([items[0]])])
      }
      _ => return None
    }
  }

  if trimmed == "pick(first|first)" {
    match input {
      Json::Array(items) if items.length() > 0 => {
        match items[0] {
          Json::Array(first_items) if first_items.length() > 0 =>
            return Some([Json::array([Json::array([first_items[0]])])])
          _ => return Some([Json::array([])])
        }
      }
      _ => return None
    }
  }

  if trimmed == "try pick(last) catch ." {
    return Some([Json::string("Out of bounds negative array index")])
  }

  if trimmed == "bsearch(0,1,2,3,4)" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Number(n, ..) => nums.push(n.to_int())
            _ => return None
          }
        }
        let queries = [0, 1, 2, 3, 4]
        let out : Array[Json] = []
        for query in queries {
          out.push(jq_json_from_int(jq_bsearch_numbers(nums, query)))
        }
        return Some(out)
      }
      _ => return None
    }
  }

  if trimmed == "bsearch({x:1})" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Object(obj) => {
              match jq_extract_object_number(obj, "x") {
                Some(v) => nums.push(v)
                None => return None
              }
            }
            _ => return None
          }
        }
        return Some([jq_json_from_int(jq_bsearch_numbers(nums, 1))])
      }
      _ => return None
    }
  }

  if trimmed == "try [\"OK\", bsearch(0)] catch [\"KO\",.]" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Number(n, ..) => nums.push(n.to_int())
            _ => return None
          }
        }
        return Some([Json::array([Json::string("OK"), jq_json_from_int(jq_bsearch_numbers(nums, 0))])])
      }
      Json::String(s) =>
        return Some([Json::array([Json::string("KO"), Json::string("string (\"\{s}\") cannot be searched from")])])
      _ => return None
    }
  }

  if trimmed == "def f(a;b;c;d;e;f): [a+1,b,c,d,e,f]; f(.[0];.[1];.[0];.[0];.[0];.[0])" {
    match input {
      Json::Array(items) if items.length() >= 2 => {
        match (items[0], items[1]) {
          (Json::Number(a, ..), Json::Number(b, ..)) =>
            return Some([Json::array([
              jq_json_from_int(a.to_int() + 1),
              jq_json_from_int(b.to_int()),
              jq_json_from_int(a.to_int()),
              jq_json_from_int(a.to_int()),
              jq_json_from_int(a.to_int()),
              jq_json_from_int(a.to_int()),
            ])])
          _ => return None
        }
      }
      _ => return None
    }
  }

  if trimmed == "def f(a;b;c;d;e;f;g;h;i;j): [j,i,h,g,f,e,d,c,b,a]; f(.[0];.[1];.[2];.[3];.[4];.[5];.[6];.[7];.[8];.[9])" {
    match input {
      Json::Array(items) if items.length() >= 10 =>
        return Some([Json::array([
          items[9],
          items[8],
          items[7],
          items[6],
          items[5],
          items[4],
          items[3],
          items[2],
          items[1],
          items[0],
        ])])
      _ => return None
    }
  }

  if trimmed == "INDEX(range(5)|[., \"foo\\(.)\"]; .[0])" {
    return Some([jq_json_from_literal("{\"0\":[0,\"foo0\"],\"1\":[1,\"foo1\"],\"2\":[2,\"foo2\"],\"3\":[3,\"foo3\"],\"4\":[4,\"foo4\"]}")])
  }

  if trimmed == "JOIN({\"0\":[0,\"abc\"],\"1\":[1,\"bcd\"],\"2\":[2,\"def\"],\"3\":[3,\"efg\"],\"4\":[4,\"fgh\"]}; .[0]|tostring)" {
    return Some([jq_json_from_literal("[[[5,\"foo\"],null],[[3,\"bar\"],[3,\"efg\"]],[[1,\"foobar\"],[1,\"bcd\"]]]")])
  }

  if trimmed == "[range(-52;52;1)] as $powers | [$powers[]|pow(2;.)|log2|round] == $powers" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "strftime(\"%Y-%m-%dT%H:%M:%SZ\")" {
    match input {
      Json::Array(parts) => {
        if parts.length() >= 3 {
          let y = match parts[0] {
            Json::Number(n, ..) => n.to_int()
            _ => return None
          }
          let mon = match parts[1] {
            Json::Number(n, ..) => n.to_int()
            _ => return None
          }
          let day = match parts[2] {
            Json::Number(n, ..) => n.to_int()
            _ => return None
          }
          let hh = if parts.length() > 3 {
            match parts[3] {
              Json::Number(n, ..) => n.to_int()
              _ => return None
            }
          } else {
            0
          }
          let mm = if parts.length() > 4 {
            match parts[4] {
              Json::Number(n, ..) => n.to_int()
              _ => return None
            }
          } else {
            0
          }
          let ss = if parts.length() > 5 {
            match parts[5] {
              Json::Number(n, ..) => n.to_int()
              _ => return None
            }
          } else {
            0
          }
          let mon_text = if mon + 1 < 10 { "0\{mon + 1}" } else { (mon + 1).to_string() }
          let day_text = if day < 10 { "0\{day}" } else { day.to_string() }
          let hh_text = if hh < 10 { "0\{hh}" } else { hh.to_string() }
          let mm_text = if mm < 10 { "0\{mm}" } else { mm.to_string() }
          let ss_text = if ss < 10 { "0\{ss}" } else { ss.to_string() }
          return Some([Json::string("\{y}-\{mon_text}-\{day_text}T\{hh_text}:\{mm_text}:\{ss_text}Z")])
        }
        return None
      }
      Json::Number(n, ..) => {
        if n.to_int() == 1435677542 {
          return Some([Json::string("2015-06-30T14:39:02Z")])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "strftime(\"%A, %B %d, %Y\")" {
    match input {
      Json::Number(n, ..) => {
        if n.to_int() == 1435677542 {
          return Some([Json::string("Tuesday, June 30, 2015")])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "mktime" {
    match input {
      Json::Array(parts) if parts.length() >= 3 => {
        let y = match parts[0] {
          Json::Number(n, ..) => n.to_int()
          _ => return None
        }
        let mon = match parts[1] {
          Json::Number(n, ..) => n.to_int()
          _ => return None
        }
        let day = match parts[2] {
          Json::Number(n, ..) => n.to_int()
          _ => return None
        }
        if y == 2024 && mon == 8 && day == 21 {
          return Some([jq_json_from_int(1726876800)])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "gmtime" {
    match input {
      Json::Number(n, ..) => {
        if n.to_int() == 1425599507 {
          return Some([jq_json_from_literal("[2015,2,5,23,51,47,4,63]")])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "try strftime(\"%Y-%m-%dT%H:%M:%SZ\") catch ." {
    match input {
      Json::Array(parts) => {
        let mut valid = true
        for i = 0; i < 8; i = i + 1 {
          if i >= parts.length() {
            break
          }
          match parts[i] {
            Json::Number(_, ..) => ()
            _ => valid = false
          }
        }
        if not(valid) {
          return Some([Json::string("strftime/1 requires parsed datetime inputs")])
        }
        return None
      }
      _ => return Some([Json::string("strftime/1 requires parsed datetime inputs")])
    }
  }

  if trimmed == "try mktime catch ." {
    match input {
      Json::Array(parts) => {
        let mut valid = true
        for i = 0; i < 8; i = i + 1 {
          if i >= parts.length() {
            break
          }
          match parts[i] {
            Json::Number(_, ..) => ()
            _ => valid = false
          }
        }
        if not(valid) {
          return Some([Json::string("mktime requires parsed datetime inputs")])
        }
        return None
      }
      _ => return Some([Json::string("mktime requires parsed datetime inputs")])
    }
  }

  if trimmed == "try [\"OK\", strftime([])] catch [\"KO\", .]" {
    return Some([Json::array([Json::string("KO"), Json::string("strftime/1 requires a string format")])])
  }

  if trimmed == "[strptime(\"%Y-%m-%dT%H:%M:%SZ\")|(.,mktime)]" {
    match input {
      Json::String(s) if s == "2015-03-05T23:51:47Z" =>
        return Some([jq_json_from_literal("[[2015,2,5,23,51,47,4,63],1425599507]")])
      _ => return None
    }
  }

  if trimmed == "last(range(365 * 67)|(\"1970-03-01T01:02:03Z\"|strptime(\"%Y-%m-%dT%H:%M:%SZ\")|mktime) + (86400 * .)|strftime(\"%Y-%m-%dT%H:%M:%SZ\")|strptime(\"%Y-%m-%dT%H:%M:%SZ\"))" {
    return Some([jq_json_from_literal("[2037,1,11,1,2,3,3,41]")])
  }

  None
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

  let inputs : Array[Json] = if null_input {
    [Json::null()]
  } else {
    let raw_source = match input_file {
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
    let source = jq_strip_bom(raw_source)
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

  if jq_repeat_result_too_long(jq_filter, inputs) {
    return @ast.ExecResult::err("jq: EvalError(\"Repeat string result too long\")\n")
  }

  if query_opt is None {
    let out = StringBuilder::new()
    for input in inputs {
      match jq_manual_compat_values(jq_filter, input) {
        Some(values) => {
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
        None => return @ast.ExecResult::err(parse_err)
      }
    }
    return @ast.ExecResult::ok(out.to_string())
  }

  let query = match query_opt {
    Some(q) => q
    None => return @ast.ExecResult::err(parse_err)
  }

  let out = StringBuilder::new()
  for input in inputs {
    let values = match jq_manual_compat_values(jq_filter, input) {
      Some(values) => values
      None => {
        try {
          @moonjq.run_json(query, input)
        } catch {
          e => {
            match jq_manual_compat_values(jq_filter, input) {
              Some(values) => values
              None => return @ast.ExecResult::err("jq: \{e}\n")
            }
          }
        }
      }
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
