// moon_bash Interpreter - Search Helpers
// Split from helpers.mbt for maintainability.

priv struct GrepTarget {
  display_path : String
  content : String
}

priv enum SedAddress {
  Line(Int)
  LastLine
  Regex(@regex.GrepMatcher)
  LastRegex
  Relative(Int)
}

priv struct SedAddressRange {
  start : SedAddress
  end : SedAddress?
}

priv struct SedRangeState {
  in_range : Bool
  relative_end_line : Int
  pending_single_line : Bool
}

priv struct SedSubstSpec {
  matcher : @regex.GrepMatcher?
  replacement : String
  global : Bool
  occurrence : Int
  literal_ampersand : Bool
  print_on_subst : Bool
  write_file : String?
}

priv struct SedTranslitSpec {
  source : String
  target : String
}

priv enum SedCommandKind {
  GroupStart
  GroupEnd
  Delete
  DeleteFirstLine
  Substitute(SedSubstSpec)
  AppendNextLine
  NextLine
  Transliterate(SedTranslitSpec)
  PrintPattern
  PrintFirstLine
  PrintLineNumber
  HoldSet
  HoldAppend
  HoldGet
  HoldAppendGet
  ExchangeHold
  AppendText(String)
  InsertText(String)
  ChangeText(String)
  WriteFile(String)
  Label(String)
  Branch(String?)
  BranchIfSubst(String?)
  BranchIfNotSubst(String?)
  VersionCheck(String?)
  Quit
}

priv struct SedCommand {
  address : SedAddressRange?
  kind : SedCommandKind
  negated : Bool
}

fn to_display_path(cwd : String, path : String) -> String {
  let prefix = cwd + "/"
  if path.has_prefix(prefix) {
    path.substring(start=prefix.length())
  } else {
    path
  }
}

fn grep_recursive_display_path(
  raw_root : String,
  resolved_root : String,
  full_path : String
) -> String {
  let mut suffix = ""
  if full_path == resolved_root {
    suffix = ""
  } else {
    let prefix = resolved_root + "/"
    if full_path.has_prefix(prefix) {
      suffix = full_path.substring(start=prefix.length())
    } else {
      // Fallback for unexpected path shapes.
      return full_path
    }
  }

  let base = if raw_root.length() == 0 { "." } else { raw_root }
  if suffix.length() == 0 {
    base
  } else if base.has_suffix("/") {
    base + suffix
  } else {
    base + "/" + suffix
  }
}

fn grep_sort_paths(paths : Array[String]) -> Unit {
  paths.sort_by(fn(a, b) {
    let min_len = if a.length() < b.length() { a.length() } else { b.length() }
    for i = 0; i < min_len; i = i + 1 {
      if a[i] < b[i] {
        return -1
      }
      if a[i] > b[i] {
        return 1
      }
    }
    if a.length() < b.length() {
      -1
    } else if a.length() > b.length() {
      1
    } else {
      0
    }
  })
}

fn path_basename(path : String) -> String {
  let mut slash = -1
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' {
      slash = i
    }
  }
  if slash < 0 {
    path
  } else if slash + 1 >= path.length() {
    ""
  } else {
    path.substring(start=slash + 1)
  }
}

fn grep_output_prefix(
  display_path : String,
  line_number : Int,
  show_filename : Bool,
  show_line_number : Bool
) -> String {
  if show_filename && show_line_number {
    display_path + ":" + line_number.to_string() + ":"
  } else if show_filename {
    display_path + ":"
  } else if show_line_number {
    line_number.to_string() + ":"
  } else {
    ""
  }
}


fn filter_word_ranges(
  ranges : Array[(Int, Int)],
  line : String,
  word_match : Bool
) -> Array[(Int, Int)] {
  if not(word_match) {
    return ranges
  }
  let filtered : Array[(Int, Int)] = []
  for range in ranges {
    if is_word_boundary(line, range.0, range.1) {
      filtered.push(range)
    }
  }
  filtered
}

fn is_word_boundary(line : String, start : Int, end : Int) -> Bool {
  let left_ok = if start <= 0 {
    true
  } else {
    not(is_word_char(line[start - 1].to_int().unsafe_to_char()))
  }
  let right_ok = if end >= line.length() {
    true
  } else {
    not(is_word_char(line[end].to_int().unsafe_to_char()))
  }
  left_ok && right_ok
}

fn is_word_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

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
  if op == 'd' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: Delete,
      negated,
    })
  }

  if op == 'D' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: DeleteFirstLine,
      negated,
    })
  }

  if op == 'p' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: PrintPattern,
      negated,
    })
  }

  if op == 'P' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: PrintFirstLine,
      negated,
    })
  }

  if op == 'N' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: AppendNextLine,
      negated,
    })
  }

  if op == 'n' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: NextLine,
      negated,
    })
  }

  if op == '=' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: PrintLineNumber,
      negated,
    })
  }

  if op == 'h' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: HoldSet,
      negated,
    })
  }

  if op == 'H' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: HoldAppend,
      negated,
    })
  }

  if op == 'g' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: HoldGet,
      negated,
    })
  }

  if op == 'G' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: HoldAppendGet,
      negated,
    })
  }

  if op == 'x' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: ExchangeHold,
      negated,
    })
  }

  if op == 'q' {
    i += 1
    if skip_ascii_space(trimmed, i) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: Quit,
      negated,
    })
  }

  if op == 'v' {
    i += 1
    let version = if i >= trimmed.length() {
      None
    } else {
      let sep = trimmed[i].to_int().unsafe_to_char()
      if sep != ' ' && sep != '\t' {
        return None
      }
      let rest = trim_ascii_space(substring_slice(trimmed, i, trimmed.length()))
      if rest.length() == 0 {
        None
      } else {
        Some(rest)
      }
    }
    return Some({
      address,
      kind: VersionCheck(version),
      negated,
    })
  }

  if op == ':' {
    i += 1
    let label = trim_ascii_space(substring_slice(trimmed, i, trimmed.length()))
    return Some({
      address,
      kind: Label(label),
      negated,
    })
  }

  if op == 'b' || op == 't' || op == 'T' {
    i += 1
    let label_text = trim_ascii_space(substring_slice(trimmed, i, trimmed.length()))
    let label = if label_text.length() == 0 {
      None
    } else {
      Some(label_text)
    }
    let kind = if op == 'b' {
      Branch(label)
    } else if op == 't' {
      BranchIfSubst(label)
    } else {
      BranchIfNotSubst(label)
    }
    return Some({
      address,
      kind,
      negated,
    })
  }

  if op == 'a' || op == 'i' || op == 'c' {
    i += 1
    guard parse_sed_text_payload(substring_slice(trimmed, i, trimmed.length())) is Some(text) else {
      return None
    }
    let kind = if op == 'a' {
      AppendText(text)
    } else if op == 'i' {
      InsertText(text)
    } else {
      ChangeText(text)
    }
    return Some({
      address,
      kind,
      negated,
    })
  }

  if op == 'w' {
    let rest = substring_slice(trimmed, i + 1, trimmed.length())
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
    return Some({
      address,
      kind: WriteFile(path),
      negated,
    })
  }

  if op == 'y' {
    i += 1
    if i >= trimmed.length() {
      return None
    }
    let delim = trimmed[i].to_int().unsafe_to_char()
    i += 1
    guard parse_sed_translit_part(trimmed, i, delim) is Some((source, target_start)) else {
      return None
    }
    guard parse_sed_translit_part(trimmed, target_start, delim) is Some((target, end_idx)) else {
      return None
    }
    if source.length() != target.length() {
      return None
    }
    if skip_ascii_space(trimmed, end_idx) != trimmed.length() {
      return None
    }
    return Some({
      address,
      kind: Transliterate({
        source,
        target,
      }),
      negated,
    })
  }

  if op != 's' {
    return None
  }

  i += 1
  if i >= trimmed.length() {
    return None
  }
  let delim = trimmed[i].to_int().unsafe_to_char()
  i += 1

  guard parse_sed_until_delim(trimmed, i, delim, regex_part=true) is Some((pattern, replacement_start)) else {
    return None
  }
  guard parse_sed_until_delim(trimmed, replacement_start, delim, regex_part=false) is Some((replacement, flags_start)) else {
    return None
  }

  let flags_text = trim_ascii_space(substring_slice(trimmed, flags_start, trimmed.length()))
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
      occurrence = parse_int_str(substring_slice(flags_text, start, j))
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

  let matcher = if pattern.length() == 0 {
    None
  } else {
    let compiled = try {
      @regex.compile_grep_matcher(
        pattern,
        extended~,
        fixed=false,
        ignore_case=ignore_case,
      )
    } catch {
      _ => return None
    }
    Some(compiled)
  }
  Some({
    address,
    kind: Substitute({
      matcher,
      replacement,
      global,
      occurrence,
      literal_ampersand: delim == '&',
      print_on_subst,
      write_file,
    }),
    negated,
  })
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
  if first == 's' ||
    first == 'd' ||
    first == 'D' ||
    first == 'N' ||
    first == 'n' ||
    first == 'y' ||
    first == '=' ||
    first == 'p' ||
    first == 'P' ||
    first == 'h' ||
    first == 'H' ||
    first == 'g' ||
    first == 'G' ||
    first == 'x' ||
    first == 'q' ||
    first == 'a' ||
    first == 'i' ||
    first == 'c' ||
    first == 'w' ||
    first == ':' ||
    first == 'b' ||
    first == 't' ||
    first == 'T' ||
    first == 'v' ||
    first == '{' {
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
    return Some((Relative(parse_int_str(substring_slice(expr, start + 1, i))), i))
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
    return Some((Line(parse_int_str(substring_slice(expr, start, i))), i))
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

fn sed_address_applies(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  state : SedRangeState,
  last_regex : @regex.GrepMatcher?
) -> (Bool, SedRangeState, @regex.GrepMatcher?) {
  match address {
    None => (
      true,
      { in_range: false, relative_end_line: -1, pending_single_line: false },
      last_regex,
    )
    Some(addr) => match addr.end {
      None => {
        let (hit, next_last) = sed_address_matches(
          addr.start,
          line,
          line_no,
          total_lines,
          last_regex,
        )
        (
          hit,
          { in_range: false, relative_end_line: -1, pending_single_line: false },
          next_last,
        )
      }
      Some(end_addr) => {
        if state.pending_single_line {
          (
            true,
            { in_range: false, relative_end_line: -1, pending_single_line: false },
            last_regex,
          )
        } else if state.in_range {
          match end_addr {
            Relative(_) => {
              if state.relative_end_line >= 0 && line_no >= state.relative_end_line {
                (
                  true,
                  { in_range: false, relative_end_line: -1, pending_single_line: false },
                  last_regex,
                )
              } else {
                (true, state, last_regex)
              }
            }
            _ => {
              let (end_hit, next_last) = sed_address_matches(
                end_addr,
                line,
                line_no,
                total_lines,
                last_regex,
              )
              (
                true,
                {
                  in_range: not(end_hit),
                  relative_end_line: -1,
                  pending_single_line: false,
                },
                next_last,
              )
            }
          }
        } else {
          let (start_hit, last_after_start) = sed_address_matches(
            addr.start,
            line,
            line_no,
            total_lines,
            last_regex,
          )
          if not(start_hit) {
            (
              false,
              { in_range: false, relative_end_line: -1, pending_single_line: false },
              last_after_start,
            )
          } else {
            match end_addr {
              Relative(count) => {
                if count <= 0 {
                  (
                    true,
                    { in_range: false, relative_end_line: -1, pending_single_line: false },
                    last_after_start,
                  )
                } else {
                  (
                    true,
                    {
                      in_range: true,
                      relative_end_line: line_no + count,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              Line(end_line) => {
                if end_line <= line_no {
                  (
                    true,
                    { in_range: false, relative_end_line: -1, pending_single_line: false },
                    last_after_start,
                  )
                } else {
                  (
                    true,
                    {
                      in_range: true,
                      relative_end_line: -1,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              _ => {
                let (end_hit, last_after_end) = sed_address_matches(
                  end_addr,
                  line,
                  line_no,
                  total_lines,
                  last_after_start,
                )
                (
                  true,
                  {
                    in_range: not(end_hit),
                    relative_end_line: -1,
                    pending_single_line: false,
                  },
                  last_after_end,
                )
              }
            }
          }
        }
      }
    }
  }
}

fn sed_address_tick_skipped(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  state : SedRangeState,
  last_regex : @regex.GrepMatcher?
) -> (SedRangeState, @regex.GrepMatcher?) {
  match address {
    None => (
      { in_range: false, relative_end_line: -1, pending_single_line: false },
      last_regex,
    )
    Some(addr) => match addr.end {
      None => {
        // Single-address commands do not carry range state across skipped cycles.
        ({ in_range: false, relative_end_line: -1, pending_single_line: false }, last_regex)
      }
      Some(end_addr) => {
        if state.pending_single_line {
          (state, last_regex)
        } else if state.in_range {
          // When a previous command deleted the cycle, this command is not executed.
          // Keep range active; end-address checks happen only on executed cycles.
          (state, last_regex)
        } else {
          let (start_hit, last_after_start) = sed_address_matches(
            addr.start,
            line,
            line_no,
            total_lines,
            last_regex,
          )
          if not(start_hit) {
            (
              { in_range: false, relative_end_line: -1, pending_single_line: false },
              last_after_start,
            )
          } else {
            match end_addr {
              Relative(count) => {
                if count <= 0 {
                  (
                    {
                      in_range: false,
                      relative_end_line: -1,
                      pending_single_line: true,
                    },
                    last_after_start,
                  )
                } else {
                  (
                    {
                      in_range: true,
                      relative_end_line: line_no + count,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              Line(end_line) => {
                if end_line <= line_no {
                  (
                    {
                      in_range: false,
                      relative_end_line: -1,
                      pending_single_line: true,
                    },
                    last_after_start,
                  )
                } else {
                  (
                    {
                      in_range: true,
                      relative_end_line: -1,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              _ => (
                { in_range: true, relative_end_line: -1, pending_single_line: false },
                last_after_start,
              )
            }
          }
        }
      }
    }
  }
}

fn sed_address_matches(
  address : SedAddress,
  line : String,
  line_no : Int,
  total_lines : Int,
  last_regex : @regex.GrepMatcher?
) -> (Bool, @regex.GrepMatcher?) {
  match address {
    Line(n) => (line_no == n, last_regex)
    LastLine => (line_no == total_lines, last_regex)
    Regex(matcher) => (matcher.find_first(line) is Some(_), Some(matcher))
    LastRegex => match last_regex {
      Some(matcher) => (matcher.find_first(line) is Some(_), last_regex)
      None => (false, None)
    }
    Relative(_) => (false, last_regex)
  }
}

fn sed_substitute_line(
  line : String,
  matcher : @regex.GrepMatcher,
  replacement : String,
  global : Bool,
  occurrence : Int,
  literal_ampersand~ : Bool = false
) -> (String, Bool) {
  if not(global) {
    if occurrence > 1 {
      let mut cursor = 0
      let mut seen = 0
      while cursor <= line.length() {
        match matcher.find_first_with_groups(line, start=cursor) {
          Some((start, end, groups)) => {
            seen += 1
            if seen == occurrence {
              let prefix = substring_slice(line, 0, start)
              let matched = substring_slice(line, start, end)
              let suffix = substring_slice(line, end, line.length())
              return (
                prefix +
                apply_sed_replacement(
                  replacement,
                  matched,
                  groups,
                  literal_ampersand~,
                ) +
                suffix,
                true,
              )
            }
            if end > start {
              cursor = end
            } else if start < line.length() {
              cursor = start + 1
            } else {
              break
            }
          }
          None => break
        }
      }
      return (line, false)
    }

    match matcher.find_first_with_groups(line) {
      Some((start, end, groups)) => {
        let prefix = substring_slice(line, 0, start)
        let matched = substring_slice(line, start, end)
        let suffix = substring_slice(line, end, line.length())
        (
          prefix +
          apply_sed_replacement(
            replacement,
            matched,
            groups,
            literal_ampersand~,
          ) +
          suffix,
          true,
        )
      }
      None => (line, false)
    }
  } else {
    let out = StringBuilder::new()
    let mut cursor = 0
    let mut changed = false
    let mut done = false
    let mut last_match_end = -1
    while not(done) {
      match matcher.find_first_with_groups(line, start=cursor) {
        Some((start, end, groups)) => {
          if start < cursor {
            done = true
          } else if start == end && start == last_match_end {
            if start < line.length() {
              out.write_char(line[start].to_int().unsafe_to_char())
              cursor = start + 1
            } else {
              cursor = line.length()
              done = true
            }
          } else {
            out.write_string(substring_slice(line, cursor, start))
            let matched = substring_slice(line, start, end)
            out.write_string(
              apply_sed_replacement(
                replacement,
                matched,
                groups,
                literal_ampersand~,
              ),
            )
            changed = true
            last_match_end = end
            if end > start {
              cursor = end
            } else if start < line.length() {
              out.write_char(line[start].to_int().unsafe_to_char())
              cursor = start + 1
            } else {
              cursor = line.length()
              done = true
            }
          }
        }
        None => done = true
      }
    }
    if cursor <= line.length() {
      out.write_string(substring_slice(line, cursor, line.length()))
    }
    if changed {
      (out.to_string(), true)
    } else {
      (line, false)
    }
  }
}

fn sed_transliterate_line(
  line : String,
  source : String,
  target : String
) -> String {
  if source.length() == 0 || target.length() == 0 {
    return line
  }
  let out = StringBuilder::new()
  for i = 0; i < line.length(); i = i + 1 {
    let ch = line[i]
    let mut replaced = false
    for j = 0; j < source.length(); j = j + 1 {
      if source[j] == ch {
        out.write_char(target[j].to_int().unsafe_to_char())
        replaced = true
        break
      }
    }
    if not(replaced) {
      out.write_char(ch.to_int().unsafe_to_char())
    }
  }
  out.to_string()
}

fn apply_sed_replacement(
  template : String,
  matched : String,
  groups : Array[String],
  literal_ampersand~ : Bool = false
) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < template.length() {
    let ch = template[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < template.length() {
        let next = template[i + 1].to_int().unsafe_to_char()
        if next == '0' {
          out.write_string(matched)
        } else if next >= '1' && next <= '9' {
          let group_idx = next.to_int() - '1'.to_int()
          if group_idx >= 0 && group_idx < groups.length() {
            out.write_string(groups[group_idx])
          }
        } else if next == 'n' {
          out.write_char('\n')
        } else if next == 't' {
          out.write_char('\t')
        } else if next == 'r' {
          out.write_char('\r')
        } else {
          out.write_char(next)
        }
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if ch == '&' && not(literal_ampersand) {
      out.write_string(matched)
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
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
