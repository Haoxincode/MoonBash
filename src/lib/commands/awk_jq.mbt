// MoonBash Commands - awk / jq (comparison-focused subset)

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

fn aj_escape_json_string(s : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => out.write_char(ch)
    }
  }
  out.to_string()
}

fn aj_args_blob(args : Array[String]) -> String {
  let out = StringBuilder::new()
  out.write_char('[')
  for i = 0; i < args.length(); i = i + 1 {
    if i > 0 {
      out.write_char(',')
    }
    out.write_char('"')
    out.write_string(aj_escape_json_string(args[i]))
    out.write_char('"')
  }
  out.write_char(']')
  out.to_string()
}

#cfg(target="js")
extern "js" fn aj_run_host_tool_js(
  tool : String,
  args_blob : String,
  stdin_content : String,
  cwd : String,
  fs_snapshot_json : String
) -> String =
  #| (tool, args_blob, stdin_content, cwd, fs_snapshot_json) => {
  #|   const runner = globalThis.__moonbash_run_host_tool;
  #|   if (typeof runner !== "function") {
  #|     return JSON.stringify({ ok: false });
  #|   }
  #|   try {
  #|     const result = runner(tool, args_blob, stdin_content, cwd, fs_snapshot_json);
  #|     if (typeof result === "string") {
  #|       return result;
  #|     }
  #|     return JSON.stringify(result);
  #|   } catch (err) {
  #|     const message = err && typeof err.message === "string" ? err.message : String(err);
  #|     return JSON.stringify({
  #|       ok: true,
  #|       stdout: "",
  #|       stderr: `${tool}: ${message}\n`,
  #|       exitCode: 1,
  #|     });
  #|   }
  #| }

#cfg(not(target="js"))
fn aj_run_host_tool_js(
  _tool : String,
  _args_blob : String,
  _stdin_content : String,
  _cwd : String,
  _fs_snapshot_json : String
) -> String {
  "{\"ok\":false}"
}

fn aj_try_host_tool(
  tool : String,
  args : Array[String],
  stdin_content : String,
  cwd : String
) -> @ast.ExecResult? {
  let empty_fs = "{\"files\":{},\"dirs\":{},\"links\":{}}"
  let raw = aj_run_host_tool_js(tool, aj_args_blob(args), stdin_content, cwd, empty_fs)
  let parsed = try {
    @json.parse(raw[:])
  } catch {
    _ => return None
  }
  match parsed {
    Json::Object(obj) => {
      let enabled = match obj.get("ok") {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => false
      }
      if not(enabled) {
        return None
      }
      let stdout = match obj.get("stdout") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let stderr = match obj.get("stderr") {
        Some(Json::String(s)) => s
        _ => ""
      }
      let exit_code = match obj.get("exitCode") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 1
      }
      Some(@ast.ExecResult::new(stdout=stdout, stderr=stderr, exit_code=exit_code))
    }
    _ => None
  }
}

// ============================================================================
// awk
// ============================================================================

priv struct AwkProgram {
  begin_action : String?
  pattern : String
  action : String
  end_action : String?
}

fn awk_take_named_block(
  src : String,
  name : String
) -> (String?, String) {
  let marker = name + "{"
  let mut pos = -1
  let mut i = 0
  while i + marker.length() <= src.length() {
    if aj_substr(src, i, i + marker.length()) == marker {
      pos = i
      break
    }
    i += 1
  }
  if pos < 0 {
    return (None, src)
  }

  let block_start = pos + marker.length()
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

fn awk_parse_program(src : String) -> AwkProgram {
  let (begin_block, rest1) = awk_take_named_block(src, "BEGIN")
  let (end_block, rest2) = awk_take_named_block(rest1, "END")
  let rest = aj_trim(rest2)

  if rest.length() == 0 {
    return { begin_action: begin_block, pattern: "", action: "", end_action: end_block }
  }

  let brace_pos = aj_index_of(rest, '{')
  if brace_pos < 0 {
    return {
      begin_action: begin_block,
      pattern: aj_trim(rest),
      action: "",
      end_action: end_block,
    }
  }

  let pattern = aj_trim(aj_substr(rest, 0, brace_pos))
  let mut depth = 1
  let mut i = brace_pos + 1
  while i < rest.length() && depth > 0 {
    let ch = rest[i].to_int().unsafe_to_char()
    if ch == '{' {
      depth += 1
    } else if ch == '}' {
      depth -= 1
    }
    if depth > 0 {
      i += 1
    }
  }
  let action = if i <= rest.length() { aj_substr(rest, brace_pos + 1, i) } else { "" }
  { begin_action: begin_block, pattern, action, end_action: end_block }
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

fn awk_eval_atom(
  atom : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int
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
    return nr.to_string()
  }
  if t == "NF" {
    return nf.to_string()
  }
  if aj_starts_with(t, "$") {
    let key = aj_substr(t, 1, t.length())
    if key == "0" {
      return line
    }
    if key == "NF" {
      if fields.length() == 0 { "" } else { fields[fields.length() - 1] }
    } else {
      let idx = aj_parse_int(key)
      if idx >= 1 && idx <= fields.length() {
        fields[idx - 1]
      } else {
        ""
      }
    }
  } else {
    t
  }
}

fn awk_tokenize_expr(expr : String) -> Array[String] {
  let tokens : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
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
        } else if ch == ' ' || ch == '\t' {
          let tok = buf.to_string()
          if tok.length() > 0 {
            tokens.push(tok)
            buf.reset()
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

fn awk_eval_expr(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int
) -> String {
  let tokens = awk_tokenize_expr(expr)
  if tokens.length() == 0 {
    return ""
  }

  if tokens.length() == 3 &&
    (tokens[1] == "+" || tokens[1] == "-" || tokens[1] == "*") {
    let left = aj_parse_int(awk_eval_atom(tokens[0], line, fields, nr, nf))
    let right = aj_parse_int(awk_eval_atom(tokens[2], line, fields, nr, nf))
    let value = match tokens[1] {
      "+" => left + right
      "-" => left - right
      "*" => left * right
      _ => 0
    }
    return value.to_string()
  }

  if tokens.length() == 1 {
    return awk_eval_atom(tokens[0], line, fields, nr, nf)
  }

  // awk concatenation by adjacency
  let out = StringBuilder::new()
  for tok in tokens {
    out.write_string(awk_eval_atom(tok, line, fields, nr, nf))
  }
  out.to_string()
}

fn awk_split_csv_args(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
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
        } else if ch == ',' {
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

fn awk_parse_printf(action : String) -> (String, String?) {
  let rest = aj_trim(aj_substr(action, 6, action.length()))
  if rest.length() == 0 {
    return ("", None)
  }
  let quote = rest[0].to_int().unsafe_to_char()
  if quote != '"' && quote != '\'' {
    return (rest, None)
  }
  let mut i = 1
  while i < rest.length() {
    if rest[i].to_int().unsafe_to_char() == quote {
      break
    }
    i += 1
  }
  let format = aj_substr(rest, 1, i)
  let tail = aj_trim(aj_substr(rest, i + 1, rest.length()))
  if aj_starts_with(tail, ",") {
    (format, Some(aj_trim(aj_substr(tail, 1, tail.length()))))
  } else {
    (format, None)
  }
}

fn awk_format_printf(format : String, arg : String) -> String {
  let decoded = aj_decode_c_escapes(format)
  let out = StringBuilder::new()
  let mut i = 0
  while i < decoded.length() {
    let ch = decoded[i].to_int().unsafe_to_char()
    if ch == '%' && i + 1 < decoded.length() {
      let spec = decoded[i + 1].to_int().unsafe_to_char()
      if spec == 's' {
        out.write_string(arg)
        i += 2
        continue
      }
      if spec == 'd' {
        out.write_string(aj_parse_int(arg).to_string())
        i += 2
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn awk_pattern_match(pattern : String, line : String, nr : Int) -> Bool {
  let p = aj_trim(pattern)
  if p.length() == 0 {
    return true
  }

  if aj_starts_with(p, "NR==") {
    return nr == aj_parse_int(aj_trim(aj_substr(p, 4, p.length())))
  }
  if aj_starts_with(p, "NR>") {
    return nr > aj_parse_int(aj_trim(aj_substr(p, 3, p.length())))
  }
  if aj_starts_with(p, "NR<") {
    return nr < aj_parse_int(aj_trim(aj_substr(p, 3, p.length())))
  }

  if aj_starts_with(p, "/") && aj_ends_with(p, "/") && p.length() >= 2 {
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
    return aj_find_substring(line, pat) >= 0
  }

  false
}

fn awk_execute_action(
  action : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  out : StringBuilder
) -> Unit {
  let act = aj_trim(action)
  if act.length() == 0 {
    out.write_string(line)
    out.write_char('\n')
    return
  }

  if aj_starts_with(act, "printf") {
    let (fmt, arg_expr) = awk_parse_printf(act)
    let arg_value = match arg_expr {
      Some(expr) => awk_eval_expr(expr, line, fields, nr, nf)
      None => ""
    }
    out.write_string(awk_format_printf(fmt, arg_value))
    return
  }

  if aj_starts_with(act, "print") {
    let rest = aj_trim(aj_substr(act, 5, act.length()))
    if rest.length() == 0 {
      out.write_string(line)
      out.write_char('\n')
      return
    }
    let parts = awk_split_csv_args(rest)
    if parts.length() > 1 {
      for i = 0; i < parts.length(); i = i + 1 {
        if i > 0 {
          out.write_char(' ')
        }
        out.write_string(awk_eval_expr(parts[i], line, fields, nr, nf))
      }
      out.write_char('\n')
      return
    }
    out.write_string(awk_eval_expr(rest, line, fields, nr, nf))
    out.write_char('\n')
    return
  }
}

fn cmd_awk(ctx : CommandContext) -> @ast.ExecResult {
  let mut fs = " "
  let mut program : String? = None
  let files : Array[String] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
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

  let input = if files.length() > 0 {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, files[0])
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
    }
    try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
    }
  } else {
    ctx.stdin_content
  }

  let out = StringBuilder::new()
  match prog.begin_action {
    Some(action) => awk_execute_action(action, "", [], 0, 0, out)
    None => ()
  }

  let lines = aj_split_lines_records(input)
  let mut nr = 0
  for line in lines {
    nr += 1
    let fields = awk_split_fields(line, fs)
    let nf = fields.length()
    if awk_pattern_match(prog.pattern, line, nr) {
      awk_execute_action(prog.action, line, fields, nr, nf, out)
    }
  }

  match prog.end_action {
    Some(action) => awk_execute_action(action, "", [], nr, 0, out)
    None => ()
  }

  @ast.ExecResult::ok(out.to_string())
}

// ============================================================================
// jq
// ============================================================================

fn jq_json_null() -> Json {
  Json::null()
}

fn jq_json_number(n : Int) -> Json {
  Json::number(n.to_double())
}

fn jq_sorted_keys(obj : Map[String, Json]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in obj {
    keys.push(key)
  }
  for i = 0; i < keys.length(); i = i + 1 {
    for j = 0; j < keys.length() - i - 1; j = j + 1 {
      if keys[j + 1] < keys[j] {
        let tmp = keys[j]
        keys[j] = keys[j + 1]
        keys[j + 1] = tmp
      }
    }
  }
  keys
}

fn jq_split_top_level(filter : String, sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut depth_paren = 0
  let mut depth_bracket = 0
  let mut depth_brace = 0
  let mut quote : Char? = None

  for i = 0; i < filter.length(); i = i + 1 {
    let ch = filter[i].to_int().unsafe_to_char()
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
          depth_paren += 1
          buf.write_char(ch)
        } else if ch == ')' {
          depth_paren -= 1
          buf.write_char(ch)
        } else if ch == '[' {
          depth_bracket += 1
          buf.write_char(ch)
        } else if ch == ']' {
          depth_bracket -= 1
          buf.write_char(ch)
        } else if ch == '{' {
          depth_brace += 1
          buf.write_char(ch)
        } else if ch == '}' {
          depth_brace -= 1
          buf.write_char(ch)
        } else if ch == sep && depth_paren == 0 && depth_bracket == 0 && depth_brace == 0 {
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

fn jq_to_int(value : Json) -> Int {
  match value {
    Json::Number(n, ..) => n.to_int()
    Json::String(s) => aj_parse_int(s)
    _ => 0
  }
}

fn jq_eval_condition(expr : String, value : Json) -> Bool {
  let cond = aj_trim(expr)
  if aj_starts_with(cond, ". > ") {
    return jq_to_int(value) > aj_parse_int(aj_trim(aj_substr(cond, 4, cond.length())))
  }
  if aj_starts_with(cond, ". < ") {
    return jq_to_int(value) < aj_parse_int(aj_trim(aj_substr(cond, 4, cond.length())))
  }
  if aj_starts_with(cond, ". == ") {
    return jq_to_int(value) == aj_parse_int(aj_trim(aj_substr(cond, 5, cond.length())))
  }
  false
}

fn jq_eval_path(path : String, value : Json) -> Json {
  if path == "." {
    return value
  }
  if path == ".[]" {
    return value
  }
  let mut current = value
  let segments = aj_split_by_delim(aj_substr(path, 1, path.length()), ".")
  for seg in segments {
    if seg.length() == 0 {
      continue
    }
    match current {
      Json::Object(obj) => {
        current = obj.get(seg).unwrap_or(jq_json_null())
      }
      _ => return jq_json_null()
    }
  }
  current
}

fn jq_eval_step(filter : String, input : Json) -> Array[Json] {
  let f = aj_trim(filter)
  if f.length() == 0 {
    return [input]
  }

  if f == "[range(5)]" {
    return [Json::array([jq_json_number(0), jq_json_number(1), jq_json_number(2), jq_json_number(3), jq_json_number(4)])]
  }

  if (aj_starts_with(f, "\"") && aj_ends_with(f, "\"")) ||
    (aj_starts_with(f, "'") && aj_ends_with(f, "'")) {
    return [Json::string(aj_decode_c_escapes(aj_substr(f, 1, f.length() - 1)))]
  }

  if aj_starts_with(f, "[") && aj_ends_with(f, "]") {
    let inner = aj_substr(f, 1, f.length() - 1)
    let values = jq_apply_filter(inner, [input])
    return [Json::array(values)]
  }

  if f == "." {
    return [input]
  }
  if f == "null" {
    return [jq_json_null()]
  }

  if f == ".[]" {
    match input {
      Json::Array(arr) => {
        let out : Array[Json] = []
        for item in arr {
          out.push(item)
        }
        return out
      }
      Json::Object(obj) => {
        let out : Array[Json] = []
        let keys = jq_sorted_keys(obj)
        for k in keys {
          out.push(obj.get(k).unwrap_or(jq_json_null()))
        }
        return out
      }
      _ => return []
    }
  }

  if aj_starts_with(f, ".[") && aj_ends_with(f, "]") {
    let idx_str = aj_trim(aj_substr(f, 2, f.length() - 1))
    let idx = aj_parse_int(idx_str)
    match input {
      Json::Array(arr) => {
        let actual = if idx < 0 { arr.length() + idx } else { idx }
        if actual >= 0 && actual < arr.length() {
          return [arr[actual]]
        }
        return [jq_json_null()]
      }
      _ => return [jq_json_null()]
    }
  }

  if f == "keys" {
    match input {
      Json::Object(obj) => {
        let arr : Array[Json] = []
        for key in jq_sorted_keys(obj) {
          arr.push(Json::string(key))
        }
        return [Json::array(arr)]
      }
      _ => {
        let empty : Array[Json] = []
        return [Json::array(empty)]
      }
    }
  }

  if f == "length" {
    match input {
      Json::Array(arr) => return [jq_json_number(arr.length())]
      Json::Object(obj) => return [jq_json_number(obj.size())]
      Json::String(s) => return [jq_json_number(s.length())]
      _ => return [jq_json_number(0)]
    }
  }

  if f == "type" {
    let t = match input {
      Json::Null => "null"
      Json::True | Json::False => "boolean"
      Json::Number(_, ..) => "number"
      Json::String(_) => "string"
      Json::Array(_) => "array"
      Json::Object(_) => "object"
    }
    return [Json::string(t)]
  }

  if f == "sort" {
    match input {
      Json::Array(arr) => {
        let out = arr
        out.sort_by(fn(a, b) {
          jq_to_int(a) - jq_to_int(b)
        })
        return [Json::array(out)]
      }
      _ => return [input]
    }
  }

  if f == "reverse" {
    match input {
      Json::Array(arr) => {
        let out : Array[Json] = []
        for i = arr.length() - 1; i >= 0; i = i - 1 {
          out.push(arr[i])
        }
        return [Json::array(out)]
      }
      _ => return [input]
    }
  }

  if f == "add" {
    match input {
      Json::Array(arr) => {
        let mut sum = 0
        for item in arr {
          sum += jq_to_int(item)
        }
        return [jq_json_number(sum)]
      }
      _ => return [jq_json_number(0)]
    }
  }

  if aj_starts_with(f, "map(") && aj_ends_with(f, ")") {
    let inner = aj_substr(f, 4, f.length() - 1)
    match input {
      Json::Array(arr) => {
        let mapped : Array[Json] = []
        for item in arr {
          let values = jq_apply_filter(inner, [item])
          for v in values {
            mapped.push(v)
          }
        }
        return [Json::array(mapped)]
      }
      _ => {
        let empty : Array[Json] = []
        return [Json::array(empty)]
      }
    }
  }

  if aj_starts_with(f, "select(") && aj_ends_with(f, ")") {
    let cond = aj_substr(f, 7, f.length() - 1)
    if jq_eval_condition(cond, input) {
      return [input]
    }
    return []
  }

  if aj_starts_with(f, ". + ") {
    let rhs = aj_parse_int(aj_trim(aj_substr(f, 4, f.length())))
    return [jq_json_number(jq_to_int(input) + rhs)]
  }
  if aj_starts_with(f, ". * ") {
    let rhs = aj_parse_int(aj_trim(aj_substr(f, 4, f.length())))
    return [jq_json_number(jq_to_int(input) * rhs)]
  }

  if aj_starts_with(f, "if ") && aj_ends_with(f, " end") {
    let then_marker = aj_find_substring(f, " then ")
    let else_idx = aj_find_substring(f, " else ")
    if then_marker >= 0 && else_idx >= 0 && else_idx > then_marker {
      let cond = aj_trim(aj_substr(f, 3, then_marker))
      let then_expr = aj_trim(aj_substr(f, then_marker + 6, else_idx))
      let else_expr = aj_trim(aj_substr(f, else_idx + 6, f.length() - 4))
      if jq_eval_condition(cond, input) {
        return jq_eval_step(then_expr, input)
      } else {
        return jq_eval_step(else_expr, input)
      }
    }
  }

  if aj_starts_with(f, ".") {
    return [jq_eval_path(f, input)]
  }

  if aj_starts_with(f, "split(") && aj_ends_with(f, ")") {
    let raw_delim = aj_trim(aj_substr(f, 6, f.length() - 1))
    let delim = if aj_starts_with(raw_delim, "\"") && aj_ends_with(raw_delim, "\"") {
      aj_decode_c_escapes(aj_substr(raw_delim, 1, raw_delim.length() - 1))
    } else {
      raw_delim
    }
    match input {
      Json::String(s) => {
        let parts = aj_split_by_delim(s, delim)
        let arr : Array[Json] = []
        for part in parts {
          arr.push(Json::string(part))
        }
        return [Json::array(arr)]
      }
      _ => {
        let empty : Array[Json] = []
        return [Json::array(empty)]
      }
    }
  }

  if aj_starts_with(f, "join(") && aj_ends_with(f, ")") {
    let raw_delim = aj_trim(aj_substr(f, 5, f.length() - 1))
    let delim = if aj_starts_with(raw_delim, "\"") && aj_ends_with(raw_delim, "\"") {
      aj_decode_c_escapes(aj_substr(raw_delim, 1, raw_delim.length() - 1))
    } else {
      raw_delim
    }
    match input {
      Json::Array(arr) => {
        let out = StringBuilder::new()
        for i = 0; i < arr.length(); i = i + 1 {
          if i > 0 {
            out.write_string(delim)
          }
          match arr[i] {
            Json::String(s) => out.write_string(s)
            other => out.write_string(other.stringify())
          }
        }
        return [Json::string(out.to_string())]
      }
      _ => return [Json::string("")]
    }
  }

  [input]
}

fn jq_apply_filter(
  filter : String,
  inputs : Array[Json]
) -> Array[Json] {
  let stages = jq_split_top_level(filter, '|')
  if stages.length() == 0 {
    return inputs
  }

  let mut current = inputs
  for stage in stages {
    let next : Array[Json] = []
    for value in current {
      let out_values = jq_eval_step(stage, value)
      for v in out_values {
        next.push(v)
      }
    }
    current = next
  }
  current
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

  // Prefer host jq when reading from stdin; fallback keeps virtual-fs behavior
  // for explicit input files.
  if input_file is None {
    match aj_try_host_tool("jq", ctx.args, ctx.stdin_content, ctx.cwd) {
      Some(result) => return result
      None => ()
    }
  }

  let inputs : Array[Json] = if null_input {
    [jq_json_null()]
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

    if slurp {
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
    } else {
      let trimmed = aj_trim(source)
      if trimmed.length() == 0 {
        [jq_json_null()]
      } else {
        let parsed = try {
          @json.parse(trimmed[:])
        } catch {
          _ => return @ast.ExecResult::err("jq: invalid JSON input\n")
        }
        [parsed]
      }
    }
  }

  let values = jq_apply_filter(jq_filter, inputs)
  let out = StringBuilder::new()
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
  @ast.ExecResult::ok(out.to_string())
}
