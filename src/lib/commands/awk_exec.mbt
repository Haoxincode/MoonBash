// moon_bash Commands - awk statement execution and cmd_awk entry point

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
