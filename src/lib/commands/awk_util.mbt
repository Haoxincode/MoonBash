// moon_bash Commands - awk field, string, number, and array utilities

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

