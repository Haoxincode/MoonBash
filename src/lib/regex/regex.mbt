// moon_bash regex helpers used by grep/sed-style commands.

pub(all) enum GrepMatcher {
  Fixed(String, Bool)
  Regex(@regexp.Regexp)
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

  let normalized = if extended { pattern } else { normalize_basic_regex(pattern) }
  let flags = if ignore_case { "i" } else { "" }
  let compiled = @regexp.compile(normalized[:], flags=flags[:])
  Regex(compiled)
}

pub fn GrepMatcher::find_first(
  self : GrepMatcher,
  line : String,
  start~ : Int = 0
) -> (Int, Int)? {
  match self {
    Fixed(pattern, ignore_case) => {
      let line_for_search = if ignore_case { to_lower_ascii(line) } else { line }
      let idx = find_substring_from(line_for_search, pattern, start)
      if idx < 0 {
        None
      } else {
        Some((idx, idx + pattern.length()))
      }
    }
    Regex(re) => {
      if start >= line.length() {
        return None
      }
      let segment = line.substring(start=start)
      let result = re.execute(segment[:])
      if not(result.matched()) {
        return None
      }
      let before_len = result.before().length()
      match result.get(0) {
        Some(matched) => {
          let begin = start + before_len
          Some((begin, begin + matched.length()))
        }
        None => None
      }
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
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < pattern.length() {
        let next = pattern[i + 1].to_int().unsafe_to_char()
        if is_bre_special_when_escaped(next) {
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
      if is_bre_literal_regex_char(ch) {
        buf.write_char('\\')
      }
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

fn is_bre_special_when_escaped(ch : Char) -> Bool {
  ch == '+' || ch == '?' || ch == '|' || ch == '(' || ch == ')' || ch == '{' || ch == '}'
}

fn is_bre_literal_regex_char(ch : Char) -> Bool {
  ch == '+' || ch == '?' || ch == '|' || ch == '(' || ch == ')' || ch == '{' || ch == '}'
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
