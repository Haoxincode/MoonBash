// moon_bash Commands - awk / jq shared helpers

// ============================================================================
// Shared Helpers (aj_ prefix)
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
    s.view(start_offset=start, end_offset=end_).to_string()
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

fn aj_first_line(s : String) -> String {
  let idx = aj_index_of(s, '\n')
  if idx >= 0 {
    aj_substr(s, 0, idx)
  } else {
    s
  }
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


fn aj_hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    return Some(ch.to_int() - '0'.to_int())
  }
  if ch >= 'a' && ch <= 'f' {
    return Some(ch.to_int() - 'a'.to_int() + 10)
  }
  if ch >= 'A' && ch <= 'F' {
    return Some(ch.to_int() - 'A'.to_int() + 10)
  }
  None
}

fn aj_octal_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '7' {
    Some(ch.to_int() - '0'.to_int())
  } else {
    None
  }
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
        'a' => { out.write_char('\u0007'); i += 2 }
        'b' => { out.write_char('\u0008'); i += 2 }
        'f' => { out.write_char('\u000c'); i += 2 }
        'v' => { out.write_char('\u000b'); i += 2 }
        '\\' => { out.write_char('\\'); i += 2 }
        '"' => { out.write_char('"'); i += 2 }
        'x' => {
          let mut value = 0
          let mut digits = 0
          let mut j = i + 2
          while j < s.length() && digits < 2 {
            match aj_hex_digit_value(s[j].to_int().unsafe_to_char()) {
              Some(d) => {
                value = value * 16 + d
                digits += 1
                j += 1
              }
              None => break
            }
          }
          if digits > 0 {
            out.write_char(value.unsafe_to_char())
            i = j
          } else {
            out.write_char('x')
            i += 2
          }
        }
        _ => {
          match aj_octal_digit_value(next) {
            Some(first) => {
              let mut value = first
              let mut j = i + 2
              let mut digits = 1
              while j < s.length() && digits < 3 {
                match aj_octal_digit_value(s[j].to_int().unsafe_to_char()) {
                  Some(d) => {
                    value = value * 8 + d
                    digits += 1
                    j += 1
                  }
                  None => break
                }
              }
              out.write_char(value.unsafe_to_char())
              i = j
            }
            None => {
              out.write_char(next)
              i += 2
            }
          }
        }
      }
    } else {
      out.write_char(ch)
      i += 1
    }
  }
  out.to_string()
}
