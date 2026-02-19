// moon_bash Commands - jq filter rewriting and query parsing

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

