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

  let decoded_pattern = decode_regex_escapes(
    if extended { pattern } else { normalize_basic_regex(pattern) },
  )
  if has_invalid_posix_char_class_syntax(decoded_pattern) {
    raise_invalid_regex()
  }
  let normalized = normalize_regex_compat(
    normalize_posix_char_classes(
      decoded_pattern,
    ),
    extended~,
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
        if !(result.matched()) {
          return None
        }
        let before_len = result.before().length()
        if before_len == 0 &&
          cursor > 0 &&
          has_bol_anchor &&
          !(accept_shifted_bol_start(re, segment)) {
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
        if !(result.matched()) {
          return None
        }
        let before_len = result.before().length()
        if before_len == 0 &&
          cursor > 0 &&
          has_bol_anchor &&
          !(accept_shifted_bol_start(re, segment)) {
            cursor += 1
            continue
        }
        match result.get(0) {
          Some(matched) => {
            let groups : Array[String] = []
            let mut group_idx = 1
            let mut done = false
            while !(done) {
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
      } else if ch == '^' && !(bre_caret_is_anchor(pattern, i)) {
        // In BRE, unescaped ^ is special at regex start or after \( / \|.
        buf.write_char('\\')
      } else if ch == '$' && !(bre_dollar_is_anchor(pattern, i)) {
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
  let mut out = pattern
  // GNU word-boundary bracket classes used by grep tests.
  out = replace_all_literal(out, "[[:<:]]", "\\b")
  out = replace_all_literal(out, "[[:>:]]", "\\b")

  // POSIX character classes commonly used in grep specs.
  out = replace_all_literal(out, "[[:alnum:]]", "[A-Za-z0-9]")
  out = replace_all_literal(out, "[[:alpha:]]", "[A-Za-z]")
  out = replace_all_literal(out, "[[:ascii:]]", "[\\x00-\\x7F]")
  out = replace_all_literal(out, "[[:blank:]]", "[ \\t]")
  out = replace_all_literal(out, "[[:cntrl:]]", "[\\x00-\\x1F\\x7F]")
  out = replace_all_literal(out, "[[:digit:]]", "[0-9]")
  out = replace_all_literal(out, "[[:graph:]]", "[!-~]")
  out = replace_all_literal(out, "[[:lower:]]", "[a-z]")
  out = replace_all_literal(out, "[[:print:]]", "[ -~]")
  out = replace_all_literal(out, "[[:punct:]]", "[!-/:-@\\[-`{-~]")
  out = replace_all_literal(out, "[[:space:]]", "[ \\t\\n\\r]")
  out = replace_all_literal(out, "[[:upper:]]", "[A-Z]")
  out = replace_all_literal(out, "[[:word:]]", "[A-Za-z0-9_]")
  out = replace_all_literal(out, "[[:xdigit:]]", "[0-9A-Fa-f]")
  out
}

fn normalize_regex_compat(pattern : String, extended~ : Bool = false) -> String {
  // Map GNU-style {,n} quantifier to engines that require {0,n}.
  let with_lower_bound = replace_all_literal(pattern, "{,", "{0,")
  // Help JS-like engines parse classes where ] is the first class member.
  let with_normalized_classes = normalize_char_class_initial_close(with_lower_bound)
  if extended {
    // In ERE, malformed interval forms like "{abc" are literals, but true intervals
    // (including BADRPT cases like "{1}" with no target) must stay intact.
    normalize_ere_malformed_intervals(with_normalized_classes)
  } else {
    // BRE keeps compatibility for leading '*' forms, but bad \{...\} should stay errors.
    normalize_invalid_quantifiers(with_normalized_classes, literalize_interval_errors=false)
  }
}

fn normalize_invalid_quantifiers(
  pattern : String,
  literalize_interval_errors~ : Bool = true
) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let mut in_char_class = false
  let mut last_repeatable = false

  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()

    if ch == '\\' {
      if i + 1 < pattern.length() {
        let next = pattern[i + 1].to_int().unsafe_to_char()
        out.write_char('\\')
        out.write_char(next)
        if in_char_class {
          last_repeatable = true
        } else if next == 'b' || next == 'B' || next == 'A' || next == 'Z' || next == 'z' {
          // Zero-width assertions should not become quantifier targets.
          last_repeatable = false
        } else {
          last_repeatable = true
        }
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }

    if in_char_class {
      out.write_char(ch)
      if ch == ']' {
        in_char_class = false
        last_repeatable = true
      }
      i += 1
      continue
    }

    if ch == '[' {
      out.write_char('[')
      in_char_class = true
      last_repeatable = false
      i += 1
      continue
    }

    if ch == '(' {
      out.write_char('(')
      last_repeatable = false
      i += 1
      continue
    }

    if ch == '|' {
      out.write_char('|')
      last_repeatable = false
      i += 1
      continue
    }

    if ch == '^' || ch == '$' {
      out.write_char(ch)
      last_repeatable = false
      i += 1
      continue
    }

    if ch == '*' || ch == '+' || ch == '?' {
      if last_repeatable {
        out.write_char(ch)
      } else {
        out.write_char('\\')
        out.write_char(ch)
      }
      last_repeatable = true
      i += 1
      continue
    }

    if ch == '{' {
      match parse_interval_quantifier(pattern, i, last_repeatable) {
        Some(length) => {
          for j = i; j < i + length; j = j + 1 {
            out.write_char(pattern[j].to_int().unsafe_to_char())
          }
          last_repeatable = true
          i += length
        }
        None => {
          if literalize_interval_errors {
            out.write_char('\\')
          }
          out.write_char('{')
          last_repeatable = literalize_interval_errors
          i += 1
        }
      }
      continue
    }

    if ch == '}' {
      if literalize_interval_errors {
        out.write_char('\\')
      }
      out.write_char('}')
      last_repeatable = literalize_interval_errors
      i += 1
      continue
    }

    out.write_char(ch)
    last_repeatable = true
    i += 1
  }

  out.to_string()
}

fn parse_interval_quantifier(
  pattern : String,
  start : Int,
  has_target : Bool
) -> Int? {
  if !(has_target) {
    return None
  }
  if start < 0 || start >= pattern.length() || pattern[start].to_int().unsafe_to_char() != '{' {
    return None
  }

  let mut i = start + 1
  let mut lower_digits = 0
  while i < pattern.length() && is_digit_char(pattern[i].to_int().unsafe_to_char()) {
    lower_digits += 1
    i += 1
  }
  if lower_digits == 0 {
    return None
  }

  if i < pattern.length() && pattern[i].to_int().unsafe_to_char() == '}' {
    return Some(i - start + 1)
  }

  if i >= pattern.length() || pattern[i].to_int().unsafe_to_char() != ',' {
    return None
  }
  i += 1

  while i < pattern.length() && is_digit_char(pattern[i].to_int().unsafe_to_char()) {
    i += 1
  }

  if i < pattern.length() && pattern[i].to_int().unsafe_to_char() == '}' {
    return Some(i - start + 1)
  }
  None
}

fn is_digit_char(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn normalize_ere_malformed_intervals(pattern : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  let mut in_char_class = false
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < pattern.length() {
        out.write_char('\\')
        out.write_char(pattern[i + 1].to_int().unsafe_to_char())
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if in_char_class {
      out.write_char(ch)
      if ch == ']' {
        in_char_class = false
      }
      i += 1
      continue
    }
    if ch == '[' {
      out.write_char('[')
      in_char_class = true
      i += 1
      continue
    }
    if ch == '{' {
      match parse_interval_syntax(pattern, i) {
        Some(length) => {
          for j = i; j < i + length; j = j + 1 {
            out.write_char(pattern[j].to_int().unsafe_to_char())
          }
          i += length
        }
        None => {
          out.write_char('\\')
          out.write_char('{')
          i += 1
        }
      }
      continue
    }
    if ch == '}' {
      out.write_char('\\')
      out.write_char('}')
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn raise_invalid_regex() -> Unit raise @regexp.RegexpError {
  // Force the regexp backend to emit a standard compile error.
  let _ = @regexp.compile("["[:])
  ()
}

fn has_invalid_posix_char_class_syntax(pattern : String) -> Bool {
  let mut i = 0
  let mut in_char_class = false
  let mut class_has_member = false
  let mut class_allow_negation = false
  while i < pattern.length() {
    let ch = pattern[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < pattern.length() {
        if in_char_class {
          class_has_member = true
          class_allow_negation = false
        }
        i += 2
      } else {
        i += 1
      }
      continue
    }

    if in_char_class {
      if class_allow_negation && ch == '^' {
        class_allow_negation = false
        i += 1
        continue
      }

      if ch == '[' &&
        i + 1 < pattern.length() &&
        pattern[i + 1].to_int().unsafe_to_char() == ':' {
          let mut j = i + 2
          let mut found_close = false
          while j + 1 < pattern.length() {
            if pattern[j].to_int().unsafe_to_char() == ':' &&
              pattern[j + 1].to_int().unsafe_to_char() == ']' {
                found_close = true
                let name = pattern.view(start_offset=i + 2, end_offset=j).to_string()
                if !(is_valid_posix_char_class_name(name)) {
                  return true
                }
                class_has_member = true
                class_allow_negation = false
                i = j + 2
                break
              }
            j += 1
          }
          if !(found_close) {
            return true
          }
          continue
        }

      if ch == ']' {
        if class_has_member {
          in_char_class = false
          class_has_member = false
          class_allow_negation = false
        } else {
          class_has_member = true
          class_allow_negation = false
        }
        i += 1
        continue
      }

      class_has_member = true
      class_allow_negation = false
      i += 1
      continue
    }

    if ch == '[' {
      in_char_class = true
      class_has_member = false
      class_allow_negation = true
      i += 1
      continue
    }

    i += 1
  }

  in_char_class
}

fn is_valid_posix_char_class_name(name : String) -> Bool {
  name == "alnum" ||
  name == "alpha" ||
  name == "ascii" ||
  name == "blank" ||
  name == "cntrl" ||
  name == "digit" ||
  name == "graph" ||
  name == "lower" ||
  name == "print" ||
  name == "punct" ||
  name == "space" ||
  name == "upper" ||
  name == "word" ||
  name == "xdigit" ||
  name == "<" ||
  name == ">" 
}

fn parse_interval_syntax(pattern : String, start : Int) -> Int? {
  if start < 0 || start >= pattern.length() || pattern[start].to_int().unsafe_to_char() != '{' {
    return None
  }

  let mut i = start + 1
  let mut lower_digits = 0
  while i < pattern.length() && is_digit_char(pattern[i].to_int().unsafe_to_char()) {
    lower_digits += 1
    i += 1
  }
  if lower_digits == 0 {
    return None
  }

  if i < pattern.length() && pattern[i].to_int().unsafe_to_char() == '}' {
    return Some(i - start + 1)
  }

  if i >= pattern.length() || pattern[i].to_int().unsafe_to_char() != ',' {
    return None
  }
  i += 1

  while i < pattern.length() && is_digit_char(pattern[i].to_int().unsafe_to_char()) {
    i += 1
  }

  if i < pattern.length() && pattern[i].to_int().unsafe_to_char() == '}' {
    return Some(i - start + 1)
  }
  None
}

fn accept_shifted_bol_start(re : @regexp.Regexp, segment : String) -> Bool {
  let probe_one = re.execute(("/" + segment)[:])
  if !(probe_one.matched()) {
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
