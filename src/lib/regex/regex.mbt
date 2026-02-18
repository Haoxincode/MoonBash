// moon_bash regex helpers used by grep/sed-style commands.

pub(all) enum GrepMatcher {
  Fixed(String, Bool)
  Regex(@regexp.Regexp, Bool)
}

pub fn compile_grep_matcher(
  pattern : String,
  extended~ : Bool = false,
  fixed~ : Bool = false,
  ignore_case~ : Bool = false
) -> GrepMatcher raise @regexp.RegexpError {
  if fixed {
    let fixed_pattern = if ignore_case { to_lower_ascii(pattern) } else { pattern }
    return Fixed(fixed_pattern, ignore_case)
  }

  let normalized = normalize_regex_compat(
    normalize_posix_char_classes(
      decode_regex_escapes(if extended { pattern } else { normalize_basic_regex(pattern) }),
    ),
  )
  let has_bol_anchor = regex_has_bol_anchor(normalized)
  let flags = if ignore_case { "i" } else { "" }
  let compiled = @regexp.compile(normalized[:], flags=flags[:])
  Regex(compiled, has_bol_anchor)
}

pub fn GrepMatcher::find_first(
  self : GrepMatcher,
  line : String,
  start~ : Int = 0
) -> (Int, Int)? {
  match self {
    Fixed(pattern, ignore_case) => {
      if start < 0 || start > line.length() {
        return None
      }
      let line_for_search = if ignore_case { to_lower_ascii(line) } else { line }
      let idx = find_substring_from(line_for_search, pattern, start)
      if idx < 0 {
        None
      } else {
        Some((idx, idx + pattern.length()))
      }
    }
    Regex(re, has_bol_anchor) => {
      if start < 0 || start > line.length() {
        return None
      }
      let mut cursor = start
      while cursor <= line.length() {
        let segment = line.view(start_offset=cursor).to_string()
        let result = re.execute(segment[:])
        if not(result.matched()) {
          return None
        }
        let before_len = result.before().length()
        if before_len == 0 &&
          cursor > 0 &&
          has_bol_anchor &&
          not(accept_shifted_bol_start(re, segment)) {
            cursor += 1
            continue
        }
        match result.get(0) {
          Some(matched) => {
            let begin = cursor + before_len
            return Some((begin, begin + matched.length()))
          }
          None => return None
        }
      }
      None
    }
  }
}

pub fn GrepMatcher::find_first_with_groups(
  self : GrepMatcher,
  line : String,
  start~ : Int = 0
) -> (Int, Int, Array[String])? {
  match self {
    Fixed(pattern, ignore_case) => {
      if start < 0 || start > line.length() {
        return None
      }
      let line_for_search = if ignore_case { to_lower_ascii(line) } else { line }
      let idx = find_substring_from(line_for_search, pattern, start)
      if idx < 0 {
        None
      } else {
        Some((idx, idx + pattern.length(), []))
      }
    }
    Regex(re, has_bol_anchor) => {
      if start < 0 || start > line.length() {
        return None
      }
      let mut cursor = start
      while cursor <= line.length() {
        let segment = line.view(start_offset=cursor).to_string()
        let result = re.execute(segment[:])
        if not(result.matched()) {
          return None
        }
        let before_len = result.before().length()
        if before_len == 0 &&
          cursor > 0 &&
          has_bol_anchor &&
          not(accept_shifted_bol_start(re, segment)) {
            cursor += 1
            continue
        }
        match result.get(0) {
          Some(matched) => {
            let groups : Array[String] = []
            let mut group_idx = 1
            let mut done = false
            while not(done) {
              match result.get(group_idx) {
                Some(group_text) => {
                  groups.push(group_text.to_string())
                  group_idx += 1
                }
                None => done = true
              }
            }
            let begin = cursor + before_len
            return Some((begin, begin + matched.length(), groups))
          }
          None => return None
        }
      }
      None
    }
  }
}

pub fn GrepMatcher::find_all(self : GrepMatcher, line : String) -> Array[(Int, Int)] {
  let ranges : Array[(Int, Int)] = []
  let mut start = 0
  while start <= line.length() {
    match self.find_first(line, start~) {
      Some((s, e)) => {
        ranges.push((s, e))
        if e > s {
          start = e
        } else {
          break
        }
      }
      None => break
    }
  }
  ranges
}

pub fn normalize_basic_regex(pattern : String) -> String {
  // Translate BRE to the ERE-like parser form:
  // unescaped + ? | ( ) { } are literals in BRE, escaped forms are operators.
  let buf = StringBuilder::new()
  let mut i = 0
  let mut in_char_class = false
  let mut class_has_member = false
  let mut class_allow_negation = false
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < pattern.length() {
        let next = pattern[i + 1].to_int().unsafe_to_char()
        if in_char_class {
          buf.write_char('\\')
          buf.write_char(next)
          class_has_member = true
          class_allow_negation = false
        } else if is_bre_special_when_escaped(next) {
          // \+ \? \| \( \) \{ \} become operators in BRE.
          buf.write_char(next)
        } else {
          // Keep other escapes as-is.
          buf.write_char('\\')
          buf.write_char(next)
        }
        i += 2
      } else {
        buf.write_char('\\')
        i += 1
      }
    } else {
      if in_char_class {
        if class_allow_negation && ch == '^' {
          // Leading ^ inside [] means complement, not an anchor.
          buf.write_char('^')
          class_allow_negation = false
          i += 1
          continue
        }
        if ch == ']' {
          if class_has_member {
            buf.write_char(']')
            in_char_class = false
            class_has_member = false
            class_allow_negation = false
          } else {
            // ] can be the first class member (e.g. [^]]).
            buf.write_char(']')
            class_has_member = true
            class_allow_negation = false
          }
          i += 1
          continue
        }
        buf.write_char(ch)
        class_has_member = true
        class_allow_negation = false
        i += 1
        continue
      }

      if ch == '[' {
        buf.write_char('[')
        in_char_class = true
        class_has_member = false
        class_allow_negation = true
        i += 1
        continue
      }

      if is_bre_literal_regex_char(ch) {
        buf.write_char('\\')
      } else if ch == '^' && not(bre_caret_is_anchor(pattern, i)) {
        // In BRE, unescaped ^ is special at regex start or after \( / \|.
        buf.write_char('\\')
      } else if ch == '$' && not(bre_dollar_is_anchor(pattern, i)) {
        // In BRE, unescaped $ is special at regex end or before \) / \|.
        buf.write_char('\\')
      }
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

fn normalize_posix_char_classes(pattern : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < pattern.length() {
    if starts_with_at(pattern, "[[:space:]]", i) {
      out.write_string("[ \\t\\n\\r]")
      i += 11
      continue
    }
    out.write_char(pattern[i].to_int().unsafe_to_char())
    i += 1
  }
  out.to_string()
}

fn normalize_regex_compat(pattern : String) -> String {
  // Map GNU-style {,n} quantifier to engines that require {0,n}.
  let with_lower_bound = replace_all_literal(pattern, "{,", "{0,")
  // Help JS-like engines parse classes where ] is the first class member.
  normalize_char_class_initial_close(with_lower_bound)
}

fn accept_shifted_bol_start(re : @regexp.Regexp, segment : String) -> Bool {
  let probe_one = re.execute(("/" + segment)[:])
  if not(probe_one.matched()) {
    return false
  }
  let before_one = probe_one.before().length()
  if before_one == 1 {
    return true
  }
  if before_one != 0 {
    return false
  }
  let probe_two = re.execute(("//" + segment)[:])
  probe_two.matched() && probe_two.before().length() > 0
}

fn regex_has_bol_anchor(pattern : String) -> Bool {
  let mut i = 0
  let mut in_char_class = false
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < pattern.length() {
        i += 2
      } else {
        i += 1
      }
      continue
    }
    if in_char_class {
      if ch == ']' {
        in_char_class = false
      }
      i += 1
      continue
    }
    if ch == '[' {
      in_char_class = true
      i += 1
      continue
    }
    if ch == '^' && ere_caret_is_anchor(pattern, i) {
      return true
    }
    i += 1
  }
  false
}

fn ere_caret_is_anchor(pattern : String, idx : Int) -> Bool {
  if idx == 0 {
    return true
  }
  let prev = pattern[idx - 1].to_int().unsafe_to_char()
  prev == '(' || prev == '|'
}

fn normalize_char_class_initial_close(pattern : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let mut in_char_class = false
  let mut class_has_member = false
  let mut class_allow_negation = false
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < pattern.length() {
        let next = pattern[i + 1].to_int().unsafe_to_char()
        out.write_char('\\')
        out.write_char(next)
        if in_char_class {
          class_has_member = true
          class_allow_negation = false
        }
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if in_char_class {
      if class_allow_negation && ch == '^' {
        out.write_char('^')
        class_allow_negation = false
        i += 1
        continue
      }
      if ch == ']' {
        if class_has_member {
          out.write_char(']')
          in_char_class = false
          class_has_member = false
          class_allow_negation = false
        } else {
          out.write_string("\\]")
          class_has_member = true
          class_allow_negation = false
        }
        i += 1
        continue
      }
      out.write_char(ch)
      class_has_member = true
      class_allow_negation = false
      i += 1
      continue
    }
    if ch == '[' {
      out.write_char('[')
      in_char_class = true
      class_has_member = false
      class_allow_negation = true
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn decode_regex_escapes(pattern : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < pattern.length() {
      let next = pattern[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => out.write_char('\n')
        't' => out.write_char('\t')
        'r' => out.write_char('\r')
        _ => {
          out.write_char('\\')
          out.write_char(next)
        }
      }
      i += 2
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn starts_with_at(text : String, token : String, idx : Int) -> Bool {
  if idx < 0 || idx + token.length() > text.length() {
    return false
  }
  for i = 0; i < token.length(); i = i + 1 {
    if text[idx + i] != token[i] {
      return false
    }
  }
  true
}

fn replace_all_literal(input : String, needle : String, replacement : String) -> String {
  if needle.length() == 0 {
    return input
  }
  let out = StringBuilder::new()
  let mut i = 0
  while i < input.length() {
    if starts_with_at(input, needle, i) {
      out.write_string(replacement)
      i += needle.length()
    } else {
      out.write_char(input[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  out.to_string()
}

fn is_bre_special_when_escaped(ch : Char) -> Bool {
  ch == '+' || ch == '?' || ch == '|' || ch == '(' || ch == ')' || ch == '{' || ch == '}'
}

fn is_bre_literal_regex_char(ch : Char) -> Bool {
  ch == '+' || ch == '?' || ch == '|' || ch == '(' || ch == ')' || ch == '{' || ch == '}'
}

fn bre_caret_is_anchor(pattern : String, idx : Int) -> Bool {
  if idx == 0 {
    return true
  }
  if idx >= 2 && pattern[idx - 2].to_int().unsafe_to_char() == '\\' {
    let prev = pattern[idx - 1].to_int().unsafe_to_char()
    if prev == '(' || prev == '|' {
      return true
    }
  }
  false
}

fn bre_dollar_is_anchor(pattern : String, idx : Int) -> Bool {
  if idx == pattern.length() - 1 {
    return true
  }
  if idx + 2 < pattern.length() && pattern[idx + 1].to_int().unsafe_to_char() == '\\' {
    let next = pattern[idx + 2].to_int().unsafe_to_char()
    if next == ')' || next == '|' {
      return true
    }
  }
  false
}

fn to_lower_ascii(s : String) -> String {
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

fn find_substring_from(haystack : String, needle : String, start : Int) -> Int {
  if needle.length() == 0 {
    return start
  }
  if start < 0 || needle.length() > haystack.length() || start > haystack.length() - needle.length() {
    return -1
  }
  let mut i = start
  while i <= haystack.length() - needle.length() {
    let mut found = true
    for j = 0; j < needle.length(); j = j + 1 {
      if haystack[i + j] != needle[j] {
        found = false
        break
      }
    }
    if found {
      return i
    }
    i += 1
  }
  -1
}
