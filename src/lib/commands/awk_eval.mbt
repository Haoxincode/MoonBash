// moon_bash Commands - awk expression evaluator and utilities

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

