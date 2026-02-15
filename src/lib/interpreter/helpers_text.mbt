// MoonBash Interpreter - Text Helpers
// Split from helpers.mbt for maintainability.

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
