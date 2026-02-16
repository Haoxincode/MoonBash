// MoonBash Filesystem Glob Pattern Matching
// Delegates matching to justjavac/glob per ecosystem-first policy.

/// Match a glob pattern against a text string.
pub fn glob_match(pattern : String, text : String) -> Bool {
  try {
    @glob.glob(pattern, text)
  } catch {
    // Keep call sites deterministic if pattern parsing fails.
    _ => false
  }
}
