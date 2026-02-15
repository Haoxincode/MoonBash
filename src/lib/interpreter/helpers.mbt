// MoonBash Interpreter - Helper Types and Utilities
// Split from interpreter.mbt for maintainability.

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

// ============================================================================
// Helper Functions
// ============================================================================

fn is_shell_builtin(name : String) -> Bool {
  match name {
    "export" | "unset" | "set" | "shift" | "exit" | "return" | "break"
    | "continue" | "read" | "test" | "[" | "printf" | "eval" | "source"
    | "." | "local" | "declare" | "typeset" | ":" | "type" | "command" | "basename"
    | "dirname" | "seq" | "rev" | "nl" | "fold" | "expand" | "unexpand" | "paste"
    | "column" | "join" | "tr" | "sort" | "uniq" | "cut" | "tee" | "sed" | "grep"
    | "egrep" | "fgrep" | "rg" | "xargs" | "date" | "env" | "printenv"
    | "which" => true
    _ => false
  }
}

fn parse_int_str(s : String) -> Int {
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

fn split_by_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' {
      let word = buf.to_string()
      if word.length() > 0 {
        result.push(word)
        buf.reset()
      }
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

fn split_lines_no_trailing(s : String) -> Array[String] {
  if s.length() == 0 {
    return []
  }
  let lines = split_lines(s)
  // Remove trailing empty line if the input ended with \n
  if lines.length() > 0 && lines[lines.length() - 1] == "" {
    let result : Array[String] = []
    for i = 0; i < lines.length() - 1; i = i + 1 {
      result.push(lines[i])
    }
    result
  } else {
    lines
  }
}

fn repeat_char(ch : Char, count : Int) -> String {
  let out = StringBuilder::new()
  let total = if count < 0 { 0 } else { count }
  for i = 0; i < total; i = i + 1 {
    out.write_char(ch)
  }
  out.to_string()
}

fn format_nl_number(number : Int, width : Int, number_format : String) -> String {
  let text = number.to_string()
  let padding = width - text.length()
  if padding <= 0 {
    return text
  }
  match number_format {
    "ln" => text + repeat_char(' ', padding)
    "rz" => repeat_char('0', padding) + text
    _ => repeat_char(' ', padding) + text
  }
}

fn fold_text(input : String, width : Int, break_spaces : Bool) -> String {
  let out = StringBuilder::new()
  let line = StringBuilder::new()

  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      out.write_string(fold_single_line(line.to_string(), width, break_spaces))
      out.write_char('\n')
      line.reset()
    } else {
      line.write_char(ch)
    }
  }

  let remaining = line.to_string()
  if remaining.length() > 0 {
    out.write_string(fold_single_line(remaining, width, break_spaces))
  }

  out.to_string()
}

fn fold_single_line(line : String, width : Int, break_spaces : Bool) -> String {
  if line.length() <= width {
    return line
  }

  let out = StringBuilder::new()
  let mut cursor = 0
  while cursor < line.length() {
    let remaining = line.length() - cursor
    if remaining <= width {
      out.write_string(substring_slice(line, cursor, line.length()))
      break
    }

    let mut cut = cursor + width
    if break_spaces {
      let mut last_blank = -1
      for i = cursor; i < cut; i = i + 1 {
        let ch = line[i].to_int().unsafe_to_char()
        if ch == ' ' || ch == '\t' {
          last_blank = i
        }
      }
      if last_blank >= cursor {
        cut = last_blank + 1
      }
    }

    if cut <= cursor {
      cut = cursor + width
    }

    out.write_string(substring_slice(line, cursor, cut))
    out.write_char('\n')
    cursor = cut
  }

  out.to_string()
}

fn expand_tabs(input : String, tab_width : Int) -> String {
  let width = if tab_width <= 0 { 8 } else { tab_width }
  let out = StringBuilder::new()
  let mut col = 0
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\t' {
      let spaces = width - (col % width)
      for j = 0; j < spaces; j = j + 1 {
        out.write_char(' ')
      }
      col += spaces
    } else {
      out.write_char(ch)
      if ch == '\n' {
        col = 0
      } else {
        col += 1
      }
    }
  }
  out.to_string()
}

fn write_unexpand_space_run(
  out : StringBuilder,
  count : Int,
  start_col : Int,
  tab_width : Int
) -> Unit {
  let mut remaining = count
  let mut col = start_col
  while remaining > 0 {
    let mut to_tab = tab_width - (col % tab_width)
    if to_tab <= 0 {
      to_tab = tab_width
    }
    if to_tab <= remaining {
      out.write_char('\t')
      col += to_tab
      remaining -= to_tab
    } else {
      out.write_char(' ')
      col += 1
      remaining -= 1
    }
  }
}

fn unexpand_tabs(input : String, tab_width : Int, convert_all : Bool) -> String {
  let width = if tab_width <= 0 { 8 } else { tab_width }
  let out = StringBuilder::new()
  let mut col = 0
  let mut leading = true
  let mut pending_spaces = 0

  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()

    if ch == ' ' {
      pending_spaces += 1
      col += 1
      continue
    }

    if pending_spaces > 0 {
      let start_col = col - pending_spaces
      if convert_all || leading {
        write_unexpand_space_run(out, pending_spaces, start_col, width)
      } else {
        out.write_string(repeat_char(' ', pending_spaces))
      }
      pending_spaces = 0
    }

    if ch == '\n' {
      out.write_char('\n')
      col = 0
      leading = true
      continue
    }

    if ch == '\t' {
      out.write_char('\t')
      let advance = width - (col % width)
      col += advance
      continue
    }

    out.write_char(ch)
    col += 1
    leading = false
  }

  if pending_spaces > 0 {
    let start_col = col - pending_spaces
    if convert_all || leading {
      write_unexpand_space_run(out, pending_spaces, start_col, width)
    } else {
      out.write_string(repeat_char(' ', pending_spaces))
    }
  }

  out.to_string()
}

fn parse_paste_delimiters(spec : String) -> Array[Char] {
  let delimiters : Array[Char] = []
  let mut i = 0
  while i < spec.length() {
    let ch = spec[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < spec.length() {
      let next = spec[i + 1].to_int().unsafe_to_char()
      let mapped = match next {
        't' => '\t'
        'n' => '\n'
        '0' => '\u0000'
        '\\' => '\\'
        _ => next
      }
      delimiters.push(mapped)
      i += 2
    } else {
      delimiters.push(ch)
      i += 1
    }
  }
  delimiters
}

fn format_column_table(input : String, separator : String?) -> String {
  let lines = split_lines_no_trailing(input)
  if lines.length() == 0 {
    return ""
  }

  let rows : Array[Array[String]] = []
  let widths : Array[Int] = []
  for line in lines {
    let fields = match separator {
      Some(delim) => split_string_by_delimiter(line, delim)
      None => split_by_whitespace(line)
    }
    rows.push(fields)
    for col = 0; col < fields.length(); col = col + 1 {
      let field_width = fields[col].length()
      if col >= widths.length() {
        widths.push(field_width)
      } else if field_width > widths[col] {
        widths[col] = field_width
      }
    }
  }

  let out = StringBuilder::new()
  for row in rows {
    for col = 0; col < row.length(); col = col + 1 {
      let field = row[col]
      out.write_string(field)
      if col + 1 < row.length() {
        let padding = widths[col] - field.length() + 2
        out.write_string(repeat_char(' ', padding))
      }
    }
    out.write_char('\n')
  }
  out.to_string()
}

fn split_join_fields(line : String, delimiter : String) -> Array[String] {
  if delimiter == " " {
    split_by_whitespace(line)
  } else {
    split_string_by_delimiter(line, delimiter)
  }
}

fn join_field_value(fields : Array[String], index : Int) -> String {
  if index >= 0 && index < fields.length() {
    fields[index]
  } else {
    ""
  }
}

fn join_parts_with_delimiter(parts : Array[String], delimiter : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out.write_string(delimiter)
    }
    out.write_string(parts[i])
  }
  out.to_string()
}

fn format_join_line(
  fields1 : Array[String],
  fields2 : Array[String],
  join_idx1 : Int,
  join_idx2 : Int,
  delimiter : String
) -> String {
  let parts : Array[String] = []
  parts.push(join_field_value(fields1, join_idx1))

  for i = 0; i < fields1.length(); i = i + 1 {
    if i != join_idx1 {
      parts.push(fields1[i])
    }
  }
  for i = 0; i < fields2.length(); i = i + 1 {
    if i != join_idx2 {
      parts.push(fields2[i])
    }
  }

  join_parts_with_delimiter(parts, delimiter)
}

fn reverse_string(s : String) -> String {
  let buf = StringBuilder::new()
  for i = s.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn to_lowercase(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'A' && ch <= 'Z' {
      buf.write_char((ch.to_int() + 32).unsafe_to_char())
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

fn contains_substring(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  for i = 0; i <= haystack.length() - needle.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < needle.length(); j = j + 1 {
      if haystack[i + j] != needle[j] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }
  false
}

fn compare_ints(a : Int, b : Int) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

fn compare_strings(a : String, b : String) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

fn ltrim_blanks(s : String) -> String {
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' {
      i += 1
    } else {
      break
    }
  }
  s.substring(start=i)
}

fn split_version_tokens(s : String) -> Array[String] {
  let tokens : Array[String] = []
  if s.length() == 0 {
    return tokens
  }
  let mut start = 0
  let mut in_digit = is_ascii_digit(s[0].to_int().unsafe_to_char())
  for i = 1; i < s.length(); i = i + 1 {
    let is_digit = is_ascii_digit(s[i].to_int().unsafe_to_char())
    if is_digit != in_digit {
      tokens.push(s.substring(start=start, end=i))
      start = i
      in_digit = is_digit
    }
  }
  tokens.push(s.substring(start=start))
  tokens
}

fn compare_version_like(a : String, b : String) -> Int {
  let ta = split_version_tokens(a)
  let tb = split_version_tokens(b)
  let max_len = if ta.length() > tb.length() { ta.length() } else { tb.length() }
  for i = 0; i < max_len; i = i + 1 {
    if i >= ta.length() {
      return -1
    }
    if i >= tb.length() {
      return 1
    }
    let sa = ta[i]
    let sb = tb[i]
    let a_num = is_numeric_token(sa)
    let b_num = is_numeric_token(sb)
    let cmp = if a_num && b_num {
      compare_ints(parse_int_str(sa), parse_int_str(sb))
    } else {
      compare_strings(sa, sb)
    }
    if cmp != 0 {
      return cmp
    }
  }
  0
}

fn is_numeric_token(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    if not(is_ascii_digit(s[i].to_int().unsafe_to_char())) {
      return false
    }
  }
  true
}

fn parse_human_size(s : String) -> Int {
  let trimmed = ltrim_blanks(s)
  if trimmed.length() == 0 {
    return 0
  }

  let mut i = 0
  if trimmed[i] == '-' || trimmed[i] == '+' {
    i += 1
  }
  while i < trimmed.length() {
    let ch = trimmed[i].to_int().unsafe_to_char()
    if is_ascii_digit(ch) || ch == '.' {
      i += 1
    } else {
      break
    }
  }
  if i == 0 {
    return 0
  }

  let number = parse_int_str(trimmed.substring(start=0, end=i))
  if i >= trimmed.length() {
    return number
  }
  let unit = ascii_upper(trimmed[i].to_int().unsafe_to_char())
  let factor = match unit {
    'K' => 1024
    'M' => 1024 * 1024
    'G' => 1024 * 1024 * 1024
    'T' => 1024 * 1024 * 1024 * 1024
    _ => 1
  }
  number * factor
}

fn ascii_upper(ch : Char) -> Char {
  if ch >= 'a' && ch <= 'z' {
    (ch.to_int() - 32).unsafe_to_char()
  } else {
    ch
  }
}

fn is_ascii_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn extract_sort_key(
  line : String,
  key_field : Int?,
  delimiter : String?,
  ignore_leading_blanks : Bool
) -> String {
  let key = match key_field {
    None => line
    Some(field) => {
      let parts = match delimiter {
        Some(delim) => split_string_by_delimiter(line, delim)
        None => split_by_whitespace(line)
      }
      if field > 0 && field <= parts.length() {
        parts[field - 1]
      } else {
        ""
      }
    }
  }
  if ignore_leading_blanks {
    ltrim_blanks(key)
  } else {
    key
  }
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

fn substring_slice(s : String, start : Int, end : Int) -> String {
  if start >= end || start < 0 || end > s.length() {
    return ""
  }
  s.substring(start=start, end=end)
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

fn expand_tr_set(s : String) -> Array[Char] {
  let result : Array[Char] = []
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < s.length() {
      let escaped = tr_unescape_char(s[i + 1].to_int().unsafe_to_char())
      result.push(escaped)
      i += 2
      continue
    }
    if i + 2 < s.length() &&
      s[i + 1].to_int().unsafe_to_char() == '-' &&
      s[i + 2].to_int().unsafe_to_char() != '\\' {
      let end_ch = s[i + 2].to_int().unsafe_to_char()
      let mut c = ch.to_int()
      while c <= end_ch.to_int() {
        result.push(c.unsafe_to_char())
        c += 1
      }
      i += 3
    } else {
      result.push(ch)
      i += 1
    }
  }
  result
}

fn tr_unescape_char(ch : Char) -> Char {
  match ch {
    'n' => '\n'
    't' => '\t'
    'r' => '\r'
    '\\' => '\\'
    _ => ch
  }
}

fn tr_set_contains(set : Array[Char], ch : Char) -> Bool {
  for c in set {
    if c == ch {
      return true
    }
  }
  false
}

fn tr_translate(set1 : Array[Char], set2 : Array[Char], ch : Char) -> Char {
  for i = 0; i < set1.length(); i = i + 1 {
    if set1[i] == ch {
      if i < set2.length() {
        return set2[i]
      } else if set2.length() > 0 {
        return set2[set2.length() - 1]
      }
    }
  }
  ch
}

fn parse_field_spec(spec : String) -> Array[Int] {
  let fields : Array[Int] = []
  let parts = split_string_by_delimiter(spec, ",")
  for part in parts {
    // Handle ranges like 1-3
    if contains_substring(part, "-") {
      let range_parts = split_string_by_delimiter(part, "-")
      if range_parts.length() == 2 {
        let start = parse_int_str(range_parts[0])
        let end = parse_int_str(range_parts[1])
        for i = start; i <= end; i = i + 1 {
          fields.push(i)
        }
      }
    } else {
      fields.push(parse_int_str(part))
    }
  }
  fields
}

fn split_string_by_delimiter(s : String, delim : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let delim_len = delim.length()
  if delim_len == 0 {
    result.push(s)
    return result
  }
  let mut i = 0
  while i < s.length() {
    let mut match_found = true
    if i + delim_len <= s.length() {
      for j = 0; j < delim_len; j = j + 1 {
        if s[i + j] != delim[j] {
          match_found = false
          break
        }
      }
    } else {
      match_found = false
    }
    if match_found {
      result.push(buf.to_string())
      buf.reset()
      i += delim_len
    } else {
      buf.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  result.push(buf.to_string())
  result
}

// ============================================================================
// Test Evaluation
// ============================================================================

fn evaluate_test(args : Array[String], ctx : ExecContext) -> Bool {
  if args.length() == 0 {
    return false
  }
  if args.length() == 1 {
    // test STRING: true if string is non-empty
    return args[0].length() > 0
  }
  if args.length() == 2 {
    let op = args[0]
    let arg = args[1]
    match op {
      "-z" => return arg.length() == 0
      "-n" => return arg.length() > 0
      "-f" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(_)) => true
          _ => false
        }
      }
      "-d" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Directory(_)) => true
          _ => false
        }
      }
      "-e" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-s" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(data)) => data.content.length() > 0
          _ => false
        }
      }
      "-r" | "-w" | "-x" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-L" | "-h" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Symlink(_)) => true
          _ => false
        }
      }
      "!" => return not(evaluate_test([arg], ctx))
      _ => ()
    }
  }
  if args.length() == 3 {
    let left = args[0]
    let op = args[1]
    let right = args[2]
    match op {
      "=" | "==" => return left == right
      "!=" => return left != right
      "-eq" => return parse_int_str(left) == parse_int_str(right)
      "-ne" => return parse_int_str(left) != parse_int_str(right)
      "-lt" => return parse_int_str(left) < parse_int_str(right)
      "-le" => return parse_int_str(left) <= parse_int_str(right)
      "-gt" => return parse_int_str(left) > parse_int_str(right)
      "-ge" => return parse_int_str(left) >= parse_int_str(right)
      "-nt" | "-ot" | "-ef" => return false // File comparison not meaningful in sandbox
      _ => ()
    }
  }
  if args.length() == 4 && args[0] == "!" {
    return not(evaluate_test([args[1], args[2], args[3]], ctx))
  }
  false
}

// ============================================================================
// Printf Implementation
// ============================================================================

fn format_printf(format : String, args : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  let mut arg_idx = 0

  while i < format.length() {
    let ch = format[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < format.length() {
      let next = format[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => { buf.write_char('\n'); i += 2 }
        't' => { buf.write_char('\t'); i += 2 }
        '\\' => { buf.write_char('\\'); i += 2 }
        '"' => { buf.write_char('"'); i += 2 }
        '0' => { buf.write_char('\u0000'); i += 2 }
        _ => { buf.write_char('\\'); buf.write_char(next); i += 2 }
      }
    } else if ch == '%' && i + 1 < format.length() {
      let spec = format[i + 1].to_int().unsafe_to_char()
      match spec {
        's' => {
          if arg_idx < args.length() {
            buf.write_string(args[arg_idx])
            arg_idx += 1
          }
          i += 2
        }
        'd' => {
          if arg_idx < args.length() {
            buf.write_string(parse_int_str(args[arg_idx]).to_string())
            arg_idx += 1
          }
          i += 2
        }
        '%' => {
          buf.write_char('%')
          i += 2
        }
        _ => {
          buf.write_char('%')
          i += 1
        }
      }
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

// ============================================================================
// Redirection Helpers
// ============================================================================

