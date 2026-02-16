// MoonBash Filesystem Glob Pattern Matching
// Delegates to justjavac/glob first, with a small compatibility fallback
// for bracket character classes that are not implemented upstream yet.

fn glob_char_at(s : String, idx : Int) -> Char {
  s[idx].to_int().unsafe_to_char()
}

fn glob_pattern_has_char_class(pattern : String) -> Bool {
  let mut i = 0
  while i < pattern.length() {
    let ch = glob_char_at(pattern, i)
    if ch == '\\' {
      i += 2
      continue
    }
    if ch == '[' {
      let mut j = i + 1
      while j < pattern.length() {
        let ch2 = glob_char_at(pattern, j)
        if ch2 == ']' {
          return true
        }
        j += 1
      }
      return false
    }
    i += 1
  }
  false
}

fn glob_class_contains(
  pattern : String,
  class_start : Int,
  target : Char
) -> (Bool, Int, Bool) {
  let mut i = class_start + 1
  if i >= pattern.length() {
    return (false, class_start + 1, false)
  }

  let mut negated = false
  let first = glob_char_at(pattern, i)
  if first == '!' || first == '^' {
    negated = true
    i += 1
  }

  let mut matched = false
  let mut has_items = false
  while i < pattern.length() {
    let ch = glob_char_at(pattern, i)
    if ch == ']' && has_items {
      let result = if negated { not(matched) } else { matched }
      return (result, i + 1, true)
    }

    if i + 2 < pattern.length() &&
      glob_char_at(pattern, i + 1) == '-' &&
      glob_char_at(pattern, i + 2) != ']' {
      let left = ch
      let right = glob_char_at(pattern, i + 2)
      has_items = true
      if (left <= target && target <= right) || (right <= target && target <= left) {
        matched = true
      }
      i += 3
      continue
    }

    has_items = true
    if ch == target {
      matched = true
    }
    i += 1
  }
  (false, class_start + 1, false)
}

fn glob_match_with_char_class(
  pattern : String,
  text : String,
  pi : Int,
  ti : Int
) -> Bool {
  if pi >= pattern.length() {
    return ti >= text.length()
  }
  let pch = glob_char_at(pattern, pi)

  if pch == '*' {
    let mut i = ti
    while i <= text.length() {
      if glob_match_with_char_class(pattern, text, pi + 1, i) {
        return true
      }
      i += 1
    }
    return false
  }

  if pch == '?' {
    if ti >= text.length() {
      return false
    }
    return glob_match_with_char_class(pattern, text, pi + 1, ti + 1)
  }

  if pch == '[' {
    if ti >= text.length() {
      return false
    }
    let target = glob_char_at(text, ti)
    let (ok, next_pi, parsed) = glob_class_contains(pattern, pi, target)
    if parsed {
      if not(ok) {
        return false
      }
      return glob_match_with_char_class(pattern, text, next_pi, ti + 1)
    }
    // Malformed class: treat '[' as a literal character.
    if target != '[' {
      return false
    }
    return glob_match_with_char_class(pattern, text, pi + 1, ti + 1)
  }

  if pch == '\\' {
    let literal = if pi + 1 < pattern.length() {
      glob_char_at(pattern, pi + 1)
    } else {
      '\\'
    }
    if ti >= text.length() || glob_char_at(text, ti) != literal {
      return false
    }
    let next_pi = if pi + 1 < pattern.length() { pi + 2 } else { pi + 1 }
    return glob_match_with_char_class(pattern, text, next_pi, ti + 1)
  }

  if ti >= text.length() || glob_char_at(text, ti) != pch {
    return false
  }
  glob_match_with_char_class(pattern, text, pi + 1, ti + 1)
}

/// Match a glob pattern against a text string.
pub fn glob_match(pattern : String, text : String) -> Bool {
  if glob_pattern_has_char_class(pattern) {
    return glob_match_with_char_class(pattern, text, 0, 0)
  }
  try {
    @glob.glob(pattern, text)
  } catch {
    // Keep call sites deterministic if pattern parsing fails.
    _ => false
  }
}
