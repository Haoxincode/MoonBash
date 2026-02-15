// MoonBash Interpreter - Search Helpers
// Split from helpers.mbt for maintainability.

priv struct GrepTarget {
  display_path : String
  content : String
}

priv enum SedAddress {
  Line(Int)
  LastLine
  Regex(@regex.GrepMatcher)
}

priv struct SedAddressRange {
  start : SedAddress
  end : SedAddress?
}

priv struct SedSubstSpec {
  matcher : @regex.GrepMatcher
  replacement : String
  global : Bool
}

priv enum SedCommandKind {
  Delete
  Substitute(SedSubstSpec)
}

priv struct SedCommand {
  address : SedAddressRange?
  kind : SedCommandKind
}

fn to_display_path(cwd : String, path : String) -> String {
  let prefix = cwd + "/"
  if path.has_prefix(prefix) {
    path.substring(start=prefix.length())
  } else {
    path
  }
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

fn parse_sed_command(
  expr : String
) -> SedCommand? {
  let trimmed = trim_ascii_space(expr)
  if trimmed.length() == 0 {
    return None
  }

  guard parse_sed_address_prefix(trimmed) is Some((address, cmd_idx)) else {
    return None
  }
  let mut i = skip_ascii_space(trimmed, cmd_idx)
  if i >= trimmed.length() {
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

  guard parse_sed_until_delim(trimmed, i, delim) is Some((pattern, replacement_start)) else {
    return None
  }
  guard parse_sed_until_delim(trimmed, replacement_start, delim) is Some((replacement, flags_start)) else {
    return None
  }

  let flags_text = trim_ascii_space(substring_slice(trimmed, flags_start, trimmed.length()))
  let mut global = false
  let mut ignore_case = false
  for j = 0; j < flags_text.length(); j = j + 1 {
    let flag = flags_text[j].to_int().unsafe_to_char()
    match flag {
      'g' => global = true
      'i' => ignore_case = true
      ' ' | '\t' | '\n' | '\r' => ()
      _ => return None
    }
  }

  let matcher = try {
    @regex.compile_grep_matcher(
      pattern,
      extended=false,
      fixed=false,
      ignore_case=ignore_case,
    )
  } catch {
    _ => return None
  }
  Some({
    address,
    kind: Substitute({
      matcher,
      replacement,
      global,
    }),
  })
}

fn parse_sed_address_prefix(
  expr : String
) -> (SedAddressRange?, Int)? {
  let i = skip_ascii_space(expr, 0)
  if i >= expr.length() {
    return None
  }
  let first = expr[i].to_int().unsafe_to_char()
  if first == 's' || first == 'd' {
    return Some((None, i))
  }

  guard parse_sed_address(expr, i) is Some((start_addr, after_start)) else {
    return None
  }

  let mut j = skip_ascii_space(expr, after_start)
  if j < expr.length() && expr[j].to_int().unsafe_to_char() == ',' {
    j += 1
    j = skip_ascii_space(expr, j)
    guard parse_sed_address(expr, j) is Some((end_addr, after_end)) else {
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
  start : Int
) -> (SedAddress, Int)? {
  if start >= expr.length() {
    return None
  }

  let ch = expr[start].to_int().unsafe_to_char()
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
    guard parse_sed_until_delim(expr, start + 1, '/') is Some((pattern, next_idx)) else {
      return None
    }
    let matcher = try {
      @regex.compile_grep_matcher(
        pattern,
        extended=false,
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
  delim : Char
) -> (String, Int)? {
  let buf = StringBuilder::new()
  let mut i = start
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
    if ch == delim {
      return Some((buf.to_string(), i + 1))
    }
    buf.write_char(ch)
    i += 1
  }
  None
}

fn sed_address_applies(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  in_range : Bool
) -> (Bool, Bool) {
  match address {
    None => (true, false)
    Some(addr) => match addr.end {
      None => (sed_address_matches(addr.start, line, line_no, total_lines), false)
      Some(end_addr) => {
        if in_range {
          let end_hit = sed_address_matches(end_addr, line, line_no, total_lines)
          (true, not(end_hit))
        } else {
          let start_hit = sed_address_matches(addr.start, line, line_no, total_lines)
          if not(start_hit) {
            (false, false)
          } else {
            let end_hit = sed_address_matches(end_addr, line, line_no, total_lines)
            (true, not(end_hit))
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
  total_lines : Int
) -> Bool {
  match address {
    Line(n) => line_no == n
    LastLine => line_no == total_lines
    Regex(matcher) => matcher.find_first(line) is Some(_)
  }
}

fn sed_substitute_line(
  line : String,
  matcher : @regex.GrepMatcher,
  replacement : String,
  global : Bool
) -> (String, Bool) {
  if not(global) {
    match matcher.find_first(line) {
      Some((start, end)) => {
        let prefix = substring_slice(line, 0, start)
        let matched = substring_slice(line, start, end)
        let suffix = substring_slice(line, end, line.length())
        (
          prefix + apply_sed_replacement(replacement, matched) + suffix,
          true,
        )
      }
      None => (line, false)
    }
  } else {
    let ranges = matcher.find_all(line)
    if ranges.length() == 0 {
      return (line, false)
    }

    let out = StringBuilder::new()
    let mut cursor = 0
    for range in ranges {
      if range.0 < cursor {
        continue
      }
      out.write_string(substring_slice(line, cursor, range.0))
      let matched = substring_slice(line, range.0, range.1)
      out.write_string(apply_sed_replacement(replacement, matched))
      cursor = range.1
    }
    out.write_string(substring_slice(line, cursor, line.length()))
    (out.to_string(), true)
  }
}

fn apply_sed_replacement(template : String, matched : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < template.length() {
    let ch = template[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < template.length() {
        let next = template[i + 1].to_int().unsafe_to_char()
        out.write_char(next)
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if ch == '&' {
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
