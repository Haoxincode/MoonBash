// moon_bash Interpreter - Sed Parser

fn trim_ascii_left(s : String) -> String {
  let i = skip_ascii_space(s, 0)
  if i <= 0 {
    s
  } else if i >= s.length() {
    ""
  } else {
    substring_slice(s, i, s.length())
  }
}

priv struct SedSubstituteFlags {
  global : Bool
  ignore_case : Bool
  occurrence : Int
  print_on_subst : Bool
  write_file : String?
}

fn parse_sed_command(
  expr : String,
  extended~ : Bool = false
) -> SedCommand? {
  let trimmed = trim_ascii_left(expr)
  if trim_ascii_space(trimmed).length() == 0 {
    return None
  }

  guard parse_sed_address_prefix(trimmed, extended~) is Some((address, cmd_idx)) else {
    return None
  }
  let mut i = skip_ascii_space(trimmed, cmd_idx)
  if i >= trimmed.length() {
    return None
  }

  let mut negated = false
  if trimmed[i].to_int().unsafe_to_char() == '!' {
    negated = true
    i = skip_ascii_space(trimmed, i + 1)
    if i >= trimmed.length() {
      return None
    }
  }
  if negated && address is None {
    return None
  }

  let op = trimmed[i].to_int().unsafe_to_char()
  match op {
    'd' => parse_sed_simple_command(trimmed, i, address, Delete, negated~)
    'D' => parse_sed_simple_command(trimmed, i, address, DeleteFirstLine, negated~)
    'p' => parse_sed_simple_command(trimmed, i, address, PrintPattern, negated~)
    'P' => parse_sed_simple_command(trimmed, i, address, PrintFirstLine, negated~)
    'N' => parse_sed_simple_command(trimmed, i, address, AppendNextLine, negated~)
    'n' => parse_sed_simple_command(trimmed, i, address, NextLine, negated~)
    '=' => parse_sed_simple_command(trimmed, i, address, PrintLineNumber, negated~)
    'h' => parse_sed_simple_command(trimmed, i, address, HoldSet, negated~)
    'H' => parse_sed_simple_command(trimmed, i, address, HoldAppend, negated~)
    'g' => parse_sed_simple_command(trimmed, i, address, HoldGet, negated~)
    'G' => parse_sed_simple_command(trimmed, i, address, HoldAppendGet, negated~)
    'x' => parse_sed_simple_command(trimmed, i, address, ExchangeHold, negated~)
    'q' => parse_sed_simple_command(trimmed, i, address, Quit, negated~)
    'v' => parse_sed_version_command(trimmed, i, address, negated~)
    ':' | 'b' | 't' | 'T' => parse_sed_flow_command(trimmed, i, address, negated~)
    'a' | 'i' | 'c' => parse_sed_text_command(trimmed, i, address, negated~)
    'w' => parse_sed_write_command(trimmed, i, address, negated~)
    'y' => parse_sed_translit_command(trimmed, i, address, negated~)
    's' => parse_sed_substitute_command(trimmed, i, address, extended~, negated~)
    _ => None
  }
}

fn parse_sed_simple_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  kind : SedCommandKind,
  negated~ : Bool = false
) -> SedCommand? {
  if skip_ascii_space(expr, op_idx + 1) != expr.length() {
    return None
  }
  Some({
    address,
    kind,
    negated,
  })
}

fn parse_sed_version_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  negated~ : Bool = false
) -> SedCommand? {
  let i = op_idx + 1
  let version = if i >= expr.length() {
    None
  } else {
    let sep = expr[i].to_int().unsafe_to_char()
    if sep != ' ' && sep != '\t' {
      return None
    }
    let rest = trim_ascii_space(substring_slice(expr, i, expr.length()))
    if rest.length() == 0 {
      None
    } else {
      Some(rest)
    }
  }
  Some({
    address,
    kind: VersionCheck(version),
    negated,
  })
}

fn parse_sed_flow_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  negated~ : Bool = false
) -> SedCommand? {
  let op = expr[op_idx].to_int().unsafe_to_char()
  let rest = trim_ascii_space(substring_slice(expr, op_idx + 1, expr.length()))
  let kind = if op == ':' {
    Label(rest)
  } else {
    let label = if rest.length() == 0 { None } else { Some(rest) }
    if op == 'b' {
      Branch(label)
    } else if op == 't' {
      BranchIfSubst(label)
    } else {
      BranchIfNotSubst(label)
    }
  }
  Some({
    address,
    kind,
    negated,
  })
}

fn parse_sed_text_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  negated~ : Bool = false
) -> SedCommand? {
  let op = expr[op_idx].to_int().unsafe_to_char()
  guard parse_sed_text_payload(substring_slice(expr, op_idx + 1, expr.length())) is Some(text) else {
    return None
  }
  let kind = if op == 'a' {
    AppendText(text)
  } else if op == 'i' {
    InsertText(text)
  } else {
    ChangeText(text)
  }
  Some({
    address,
    kind,
    negated,
  })
}

fn parse_sed_write_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  negated~ : Bool = false
) -> SedCommand? {
  let rest = substring_slice(expr, op_idx + 1, expr.length())
  let has_space = rest.length() > 0 && (
    rest[0].to_int().unsafe_to_char() == ' ' ||
    rest[0].to_int().unsafe_to_char() == '\t'
  )
  if address is None && not(has_space) {
    return None
  }
  let path = trim_ascii_space(rest)
  if path.length() == 0 {
    return None
  }
  Some({
    address,
    kind: WriteFile(path),
    negated,
  })
}

fn parse_sed_translit_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  negated~ : Bool = false
) -> SedCommand? {
  let mut i = op_idx + 1
  if i >= expr.length() {
    return None
  }
  let delim = expr[i].to_int().unsafe_to_char()
  i += 1
  guard parse_sed_translit_part(expr, i, delim) is Some((source, target_start)) else {
    return None
  }
  guard parse_sed_translit_part(expr, target_start, delim) is Some((target, end_idx)) else {
    return None
  }
  if source.length() != target.length() {
    return None
  }
  if skip_ascii_space(expr, end_idx) != expr.length() {
    return None
  }
  Some({
    address,
    kind: Transliterate({
      source,
      target,
    }),
    negated,
  })
}

fn parse_sed_substitute_command(
  expr : String,
  op_idx : Int,
  address : SedAddressRange?,
  extended~ : Bool = false,
  negated~ : Bool = false
) -> SedCommand? {
  guard parse_sed_substitute_parts(expr, op_idx) is Some((pattern, replacement, flags_text, delim)) else {
    return None
  }
  guard parse_sed_substitute_flags(flags_text) is Some(flags) else {
    return None
  }
  let matcher = parse_sed_substitute_matcher(pattern, extended~, ignore_case=flags.ignore_case)
  if pattern.length() > 0 && matcher is None {
    return None
  }

  Some({
    address,
    kind: Substitute({
      matcher,
      replacement,
      global: flags.global,
      occurrence: flags.occurrence,
      literal_ampersand: delim == '&',
      print_on_subst: flags.print_on_subst,
      write_file: flags.write_file,
    }),
    negated,
  })
}

fn parse_sed_substitute_parts(
  expr : String,
  op_idx : Int
) -> (String, String, String, Char)? {
  let mut i = op_idx + 1
  if i >= expr.length() {
    return None
  }
  let delim = expr[i].to_int().unsafe_to_char()
  i += 1

  guard parse_sed_until_delim(expr, i, delim, regex_part=true) is Some((pattern, replacement_start)) else {
    return None
  }
  guard parse_sed_until_delim(expr, replacement_start, delim, regex_part=false) is Some((replacement, flags_start)) else {
    return None
  }

  let flags_text = trim_ascii_space(substring_slice(expr, flags_start, expr.length()))
  Some((pattern, replacement, flags_text, delim))
}

fn parse_sed_substitute_flags(flags_text : String) -> SedSubstituteFlags? {
  let mut global = false
  let mut ignore_case = false
  let mut occurrence = 1
  let mut print_on_subst = false
  let mut write_file : String? = None
  let mut j = 0
  while j < flags_text.length() {
    let flag = flags_text[j].to_int().unsafe_to_char()
    if flag >= '0' && flag <= '9' {
      let start = j
      while j < flags_text.length() {
        let digit = flags_text[j].to_int().unsafe_to_char()
        if digit >= '0' && digit <= '9' {
          j += 1
        } else {
          break
        }
      }
      occurrence = parse_int32_str(substring_slice(flags_text, start, j))
      if occurrence <= 0 {
        return None
      }
      continue
    }
    match flag {
      'g' => global = true
      'i' | 'I' => ignore_case = true
      'p' => print_on_subst = true
      'w' => {
        let path = trim_ascii_space(substring_slice(flags_text, j + 1, flags_text.length()))
        if path.length() == 0 {
          return None
        }
        write_file = Some(path)
        j = flags_text.length()
        continue
      }
      ' ' | '\t' | '\n' | '\r' => ()
      _ => return None
    }
    j += 1
  }
  Some({
    global,
    ignore_case,
    occurrence,
    print_on_subst,
    write_file,
  })
}

fn parse_sed_substitute_matcher(
  pattern : String,
  extended~ : Bool = false,
  ignore_case~ : Bool = false
) -> @regex.GrepMatcher? {
  if pattern.length() == 0 {
    return None
  }
  let compiled = try {
    @regex.compile_grep_matcher(
      pattern,
      extended~,
      fixed=false,
      ignore_case~,
    )
  } catch {
    _ => {
      if sed_pattern_has_regex_meta(pattern) {
        return None
      }
      try {
        @regex.compile_grep_matcher(
          pattern,
          extended~,
          fixed=true,
          ignore_case~,
        )
      } catch {
        _ => return None
      }
    }
  }
  Some(compiled)
}

fn sed_pattern_has_regex_meta(pattern : String) -> Bool {
  for i = 0; i < pattern.length(); i = i + 1 {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '.' ||
      ch == '*' ||
      ch == '+' ||
      ch == '?' ||
      ch == '^' ||
      ch == '$' ||
      ch == '[' ||
      ch == ']' ||
      ch == '(' ||
      ch == ')' ||
      ch == '{' ||
      ch == '}' ||
      ch == '|' ||
      ch == '\\' {
      return true
    }
  }
  false
}

fn parse_sed_address_prefix(
  expr : String,
  extended~ : Bool = false
) -> (SedAddressRange?, Int)? {
  let i = skip_ascii_space(expr, 0)
  if i >= expr.length() {
    return None
  }
  let first = expr[i].to_int().unsafe_to_char()
  if is_sed_command_start_char(first) {
    return Some((None, i))
  }

  guard parse_sed_address(expr, i, extended~, allow_relative=false) is Some((start_addr, after_start)) else {
    return None
  }

  let mut j = skip_ascii_space(expr, after_start)
  if j < expr.length() && expr[j].to_int().unsafe_to_char() == ',' {
    j += 1
    j = skip_ascii_space(expr, j)
    guard parse_sed_address(expr, j, extended~, allow_relative=true) is Some((end_addr, after_end)) else {
      return None
    }
    Some((
      Some({
        start: start_addr,
        end: Some(end_addr),
      }),
      after_end,
    ))
  } else {
    Some((
      Some({
        start: start_addr,
        end: None,
      }),
      j,
    ))
  }
}

fn is_sed_command_start_char(ch : Char) -> Bool {
  ch == 's' ||
  ch == 'd' ||
  ch == 'D' ||
  ch == 'N' ||
  ch == 'n' ||
  ch == 'y' ||
  ch == '=' ||
  ch == 'p' ||
  ch == 'P' ||
  ch == 'h' ||
  ch == 'H' ||
  ch == 'g' ||
  ch == 'G' ||
  ch == 'x' ||
  ch == 'q' ||
  ch == 'a' ||
  ch == 'i' ||
  ch == 'c' ||
  ch == 'w' ||
  ch == ':' ||
  ch == 'b' ||
  ch == 't' ||
  ch == 'T' ||
  ch == 'v' ||
  ch == '{'
}

fn parse_sed_address(
  expr : String,
  start : Int,
  extended~ : Bool = false,
  allow_relative~ : Bool = false
) -> (SedAddress, Int)? {
  if start >= expr.length() {
    return None
  }

  let ch = expr[start].to_int().unsafe_to_char()
  if allow_relative && ch == '+' {
    let mut i = start + 1
    if i >= expr.length() {
      return None
    }
    while i < expr.length() {
      let next = expr[i].to_int().unsafe_to_char()
      if next >= '0' && next <= '9' {
        i += 1
      } else {
        break
      }
    }
    if i == start + 1 {
      return None
    }
    return Some((Relative(parse_int32_str(substring_slice(expr, start + 1, i))), i))
  }
  if ch == '$' {
    return Some((LastLine, start + 1))
  }
  if ch >= '0' && ch <= '9' {
    let mut i = start + 1
    while i < expr.length() {
      let next = expr[i].to_int().unsafe_to_char()
      if next >= '0' && next <= '9' {
        i += 1
      } else {
        break
      }
    }
    return Some((Line(parse_int32_str(substring_slice(expr, start, i))), i))
  }
  if ch == '/' {
    guard parse_sed_until_delim(expr, start + 1, '/', regex_part=true) is Some((pattern, next_idx)) else {
      return None
    }
    if pattern.length() == 0 {
      return Some((LastRegex, next_idx))
    }
    let matcher = try {
      @regex.compile_grep_matcher(
        pattern,
        extended~,
        fixed=false,
        ignore_case=false,
      )
    } catch {
      _ => return None
    }
    return Some((Regex(matcher), next_idx))
  }

  None
}

fn parse_sed_until_delim(
  expr : String,
  start : Int,
  delim : Char,
  regex_part~ : Bool = false
) -> (String, Int)? {
  let buf = StringBuilder::new()
  let mut i = start
  let mut in_char_class = false
  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 >= expr.length() {
        buf.write_char('\\')
        i += 1
        continue
      }
      let next = expr[i + 1].to_int().unsafe_to_char()
      if next == delim {
        buf.write_char(delim)
      } else {
        buf.write_char('\\')
        buf.write_char(next)
      }
      i += 2
      continue
    }
    if regex_part {
      if ch == '[' && not(in_char_class) {
        in_char_class = true
      } else if ch == ']' && in_char_class {
        in_char_class = false
      }
    }
    if ch == delim && not(in_char_class) {
      return Some((buf.to_string(), i + 1))
    }
    buf.write_char(ch)
    i += 1
  }
  None
}

fn parse_sed_translit_part(
  expr : String,
  start : Int,
  delim : Char
) -> (String, Int)? {
  let buf = StringBuilder::new()
  let mut i = start
  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()
    if ch == delim {
      return Some((buf.to_string(), i + 1))
    }
    if ch == '\\' {
      if i + 1 >= expr.length() {
        return None
      }
      let next = expr[i + 1].to_int().unsafe_to_char()
      match next {
        'n' | '\n' => buf.write_char('\n')
        't' => buf.write_char('\t')
        'r' => buf.write_char('\r')
        _ => buf.write_char(next)
      }
      i += 2
      continue
    }
    buf.write_char(ch)
    i += 1
  }
  None
}

fn parse_sed_text_payload(raw : String) -> String? {
  let mut i = 0
  while i < raw.length() {
    let ch = raw[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' {
      i += 1
    } else {
      break
    }
  }
  if i >= raw.length() {
    return None
  }

  let mut payload = substring_slice(raw, i, raw.length())
  if payload[0].to_int().unsafe_to_char() == '\\' && (
    payload.length() == 1 ||
    payload[1].to_int().unsafe_to_char() == '\n' ||
    payload[1].to_int().unsafe_to_char() == ' ' ||
    payload[1].to_int().unsafe_to_char() == '\t'
  ) {
    payload = substring_slice(payload, 1, payload.length())
    if payload.length() > 0 && payload[0].to_int().unsafe_to_char() == '\n' {
      payload = substring_slice(payload, 1, payload.length())
    }
  }
  if payload.length() == 0 {
    return None
  }
  Some(decode_sed_escapes(payload))
}

fn decode_sed_escapes(text : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    let ch = text[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < text.length() {
      let next = text[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => out.write_char('\n')
        't' => out.write_char('\t')
        'r' => out.write_char('\r')
        _ => out.write_char(next)
      }
      i += 2
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn parse_sed_inline_directives(expr : String) -> (Bool, Bool)? {
  let trimmed = trim_ascii_left(expr)
  if trimmed.length() < 2 || trimmed[0].to_int().unsafe_to_char() != '#' {
    return None
  }

  let mut quiet = false
  let mut extended = false
  let mut saw_flag = false
  let mut i = 1
  while i < trimmed.length() {
    let ch = trimmed[i].to_int().unsafe_to_char()
    match ch {
      'n' => {
        quiet = true
        saw_flag = true
      }
      'r' | 'E' => {
        extended = true
        saw_flag = true
      }
      ' ' | '\t' | '\r' | '\n' => ()
      _ => return None
    }
    i += 1
  }

  if saw_flag {
    Some((quiet, extended))
  } else {
    None
  }
}

fn parse_sed_script_commands(
  expr : String,
  extended~ : Bool = false
) -> Array[SedCommand]? {
  let normalized = trim_ascii_left(expr)
  if trim_ascii_space(normalized).length() == 0 {
    return Some([])
  }

  let (segments, separators) = split_sed_top_level_parts(normalized)
  if separators.length() == 0 {
    return parse_sed_single_piece(normalized, extended~)
  }

  let merged : Array[SedCommand] = []
  let mut seg_idx = 0
  while seg_idx < segments.length() {
    let mut candidate = segments[seg_idx]
    let mut sep_idx = seg_idx
    let mut parsed = parse_sed_single_piece(candidate, extended~)
    while parsed is None && sep_idx < separators.length() {
      if sep_idx - seg_idx >= 12 {
        return None
      }
      candidate = candidate + separators[sep_idx] + segments[sep_idx + 1]
      sep_idx += 1
      parsed = parse_sed_single_piece(candidate, extended~)
    }
    guard parsed is Some(cmds) else {
      return None
    }
    for cmd in cmds {
      merged.push(cmd)
    }
    seg_idx = sep_idx + 1
  }

  Some(merged)
}

fn parse_sed_single_piece(
  expr : String,
  extended~ : Bool = false
) -> Array[SedCommand]? {
  let trimmed = trim_ascii_left(expr)
  if trim_ascii_space(trimmed).length() == 0 {
    return Some([])
  }
  if trimmed[0].to_int().unsafe_to_char() == '#' {
    return Some([])
  }

  match parse_sed_command(trimmed, extended~) {
    Some(cmd) => return Some([cmd])
    None => ()
  }

  match parse_sed_group_commands(trimmed, extended~) {
    Some(cmds) => return Some(cmds)
    None => ()
  }

  None
}

fn parse_sed_group_commands(
  expr : String,
  extended~ : Bool = false
) -> Array[SedCommand]? {
  guard parse_sed_group_open(expr, extended~) is Some((address, outer_negated, open_idx)) else {
    return None
  }
  guard parse_sed_group_close_index(expr, open_idx) is Some(close_idx) else {
    return None
  }
  if skip_ascii_space(expr, close_idx + 1) != expr.length() {
    return None
  }

  let inner = substring_slice(expr, open_idx + 1, close_idx)
  guard parse_sed_script_commands(inner, extended~) is Some(inner_cmds) else {
    return None
  }

  let wrapped : Array[SedCommand] = []
  wrapped.push({
    address,
    kind: GroupStart,
    negated: outer_negated,
  })
  for cmd in inner_cmds {
    wrapped.push(cmd)
  }
  wrapped.push({
    address: None,
    kind: GroupEnd,
    negated: false,
  })
  Some(wrapped)
}

fn parse_sed_group_open(
  expr : String,
  extended~ : Bool = false
) -> (SedAddressRange?, Bool, Int)? {
  guard parse_sed_address_prefix(expr, extended~) is Some((address, cmd_idx)) else {
    return None
  }

  let mut open_idx = skip_ascii_space(expr, cmd_idx)
  let mut outer_negated = false
  if open_idx < expr.length() && expr[open_idx].to_int().unsafe_to_char() == '!' {
    outer_negated = true
    open_idx = skip_ascii_space(expr, open_idx + 1)
  }
  if outer_negated && address is None {
    return None
  }
  if open_idx >= expr.length() || expr[open_idx].to_int().unsafe_to_char() != '{' {
    return None
  }

  Some((address, outer_negated, open_idx))
}

fn parse_sed_group_close_index(expr : String, open_idx : Int) -> Int? {
  let mut depth = 1
  let mut i = open_idx + 1
  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()
    if ch == '\\' {
      i += 2
      continue
    }
    if ch == '{' {
      depth += 1
      i += 1
      continue
    }
    if ch == '}' {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
      i += 1
      continue
    }
    i += 1
  }
  None
}

fn split_sed_top_level_parts(expr : String) -> (Array[String], Array[String]) {
  let segments : Array[String] = []
  let separators : Array[String] = []
  let mut start = 0
  let mut brace_depth = 0
  let mut escaped = false
  for i = 0; i < expr.length(); i = i + 1 {
    let ch = expr[i].to_int().unsafe_to_char()
    if escaped {
      escaped = false
      continue
    }
    if ch == '\\' {
      escaped = true
      continue
    }
    if ch == '{' {
      brace_depth += 1
      continue
    }
    if ch == '}' {
      if brace_depth > 0 {
        brace_depth -= 1
      }
      continue
    }
    if (ch == ';' || ch == '\n') && brace_depth == 0 {
      segments.push(substring_slice(expr, start, i))
      separators.push(if ch == ';' { ";" } else { "\n" })
      start = i + 1
    }
  }
  segments.push(substring_slice(expr, start, expr.length()))
  (segments, separators)
}

fn skip_ascii_space(s : String, start : Int) -> Int {
  let mut i = start
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      i += 1
    } else {
      break
    }
  }
  i
}

fn trim_ascii_space(s : String) -> String {
  let start = skip_ascii_space(s, 0)
  if start >= s.length() {
    return ""
  }
  let mut end = s.length()
  while end > start {
    let ch = s[end - 1].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      end -= 1
    } else {
      break
    }
  }
  substring_slice(s, start, end)
}
