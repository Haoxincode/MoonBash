// moon_bash Commands - awk parser (types, constants, program structure)

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
