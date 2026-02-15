// MoonBash Filesystem Glob Pattern Matching

/// Match a glob pattern against a text string.
/// Supports `*`, `?`, and basic character classes (`[abc]`, `[a-z]`, `[^x]`).
pub fn glob_match(pattern : String, text : String) -> Bool {
  glob_match_impl(pattern, 0, text, 0)
}

/// Recursive implementation of glob matching.
fn glob_match_impl(
  pattern : String,
  pi : Int,
  text : String,
  ti : Int
) -> Bool {
  let plen = pattern.length()
  let tlen = text.length()
  if pi >= plen && ti >= tlen {
    return true
  }
  if pi >= plen {
    return false
  }

  let pc = pattern[pi].to_int().unsafe_to_char()
  if pc == '*' {
    // Collapse consecutive '*'.
    let mut next_pi = pi
    while next_pi < plen &&
      pattern[next_pi].to_int().unsafe_to_char() == '*' {
      next_pi += 1
    }
    if next_pi >= plen {
      return true
    }
    let mut try_ti = ti
    while try_ti <= tlen {
      if glob_match_impl(pattern, next_pi, text, try_ti) {
        return true
      }
      try_ti += 1
    }
    return false
  }

  if ti >= tlen {
    return false
  }

  if pc == '?' {
    return glob_match_impl(pattern, pi + 1, text, ti + 1)
  }

  if pc == '[' {
    let bracket_end = glob_find_closing_bracket(pattern, pi + 1)
    if bracket_end < 0 {
      // Treat unmatched '[' as a literal character.
      if pattern[pi] == text[ti] {
        return glob_match_impl(pattern, pi + 1, text, ti + 1)
      }
      return false
    }
    let matched = glob_char_class_match(pattern, pi + 1, bracket_end, text[ti].to_int().unsafe_to_char())
    if not(matched) {
      return false
    }
    return glob_match_impl(pattern, bracket_end + 1, text, ti + 1)
  }

  if pattern[pi] == text[ti] {
    return glob_match_impl(pattern, pi + 1, text, ti + 1)
  }
  false
}

fn glob_find_closing_bracket(pattern : String, start : Int) -> Int {
  let mut i = start
  while i < pattern.length() {
    if pattern[i].to_int().unsafe_to_char() == ']' {
      return i
    }
    i += 1
  }
  -1
}

fn glob_char_class_match(
  pattern : String,
  start : Int,
  end_ : Int,
  ch : Char
) -> Bool {
  if start >= end_ {
    return false
  }

  let mut i = start
  let mut negated = false
  if i < end_ {
    let first = pattern[i].to_int().unsafe_to_char()
    if first == '!' || first == '^' {
      negated = true
      i += 1
    }
  }

  let mut matched = false
  while i < end_ {
    let current = pattern[i].to_int().unsafe_to_char()
    // Range syntax: a-z
    if i + 2 < end_ &&
      pattern[i + 1].to_int().unsafe_to_char() == '-' {
      let range_end = pattern[i + 2].to_int().unsafe_to_char()
      let lo = if current <= range_end { current } else { range_end }
      let hi = if current <= range_end { range_end } else { current }
      if ch >= lo && ch <= hi {
        matched = true
      }
      i += 3
      continue
    }

    if ch == current {
      matched = true
    }
    i += 1
  }

  if negated { not(matched) } else { matched }
}
