// MoonBash Filesystem Glob Pattern Matching (minimal Phase 1)

/// Match a glob pattern against a text string.
/// Supports `*` (any characters) and `?` (one character).
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
  // Both exhausted: match
  if pi >= plen && ti >= tlen {
    return true
  }
  // Pattern exhausted but text remains: no match
  if pi >= plen {
    return false
  }
  let pc = pattern[pi]
  // Handle '*': match zero or more characters
  if pc == '*' {
    // Skip consecutive stars
    let mut next_pi = pi
    while next_pi < plen && pattern[next_pi] == '*' {
      next_pi = next_pi + 1
    }
    // If star is at end of pattern, match everything
    if next_pi >= plen {
      return true
    }
    // Try matching rest of pattern starting at each position in text
    let mut try_ti = ti
    while try_ti <= tlen {
      if glob_match_impl(pattern, next_pi, text, try_ti) {
        return true
      }
      try_ti = try_ti + 1
    }
    return false
  }
  // Text exhausted but pattern has non-star chars: no match
  if ti >= tlen {
    return false
  }
  // Handle '?': match any single character
  if pc == '?' {
    return glob_match_impl(pattern, pi + 1, text, ti + 1)
  }
  // Literal character match
  if pc == text[ti] {
    return glob_match_impl(pattern, pi + 1, text, ti + 1)
  }
  false
}
