// moon_bash Commands - awk statement parsing, conditions, and pattern matching

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

