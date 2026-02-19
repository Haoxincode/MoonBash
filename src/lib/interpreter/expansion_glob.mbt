// ============================================================================
// Brace Expansion
// ============================================================================

let brace_expansion_result_limit : Int = 10_000

fn expand_brace_literal(s : String) -> Array[String] {
  let out : Array[String] = []
  brace_expand_collect(s, out)
  if out.length() == 0 {
    [s]
  } else {
    out
  }
}

fn brace_expand_collect(input : String, out : Array[String]) -> Unit {
  if out.length() >= brace_expansion_result_limit {
    return
  }
  match find_first_brace_pair(input) {
    None => out.push(input)
    Some((start, end_)) => {
      let content = input.view(start_offset=start + 1, end_offset=end_).to_string()
      let options = parse_brace_options(content)
      if options.length() == 0 {
        out.push(input)
        return
      }
      let prefix = input.view(start_offset=0, end_offset=start).to_string()
      let suffix = input.view(start_offset=end_ + 1).to_string()
      for option in options {
        if out.length() >= brace_expansion_result_limit {
          return
        }
        brace_expand_collect(prefix + option + suffix, out)
      }
    }
  }
}

fn find_first_brace_pair(s : String) -> (Int, Int)? {
  let mut i = 0
  while i < s.length() {
    if s[i] == '{' {
      let mut depth = 1
      let mut j = i + 1
      while j < s.length() {
        if s[j] == '{' {
          depth += 1
        } else if s[j] == '}' {
          depth -= 1
          if depth == 0 {
            return Some((i, j))
          }
        }
        j += 1
      }
      return None
    }
    i += 1
  }
  None
}

fn parse_brace_options(content : String) -> Array[String] {
  let (comma_options, has_comma) = split_brace_top_level_commas(content)
  if has_comma {
    return comma_options
  }

  let range_options = parse_brace_range(content)
  if range_options.length() > 0 {
    return range_options
  }
  []
}

fn split_brace_top_level_commas(content : String) -> (Array[String], Bool) {
  let parts : Array[String] = []
  let mut depth = 0
  let mut start = 0
  let mut has_comma = false

  for i = 0; i < content.length(); i = i + 1 {
    if content[i] == '{' {
      depth += 1
    } else if content[i] == '}' {
      if depth > 0 {
        depth -= 1
      }
    } else if content[i] == ',' && depth == 0 {
      parts.push(content.view(start_offset=start, end_offset=i).to_string())
      start = i + 1
      has_comma = true
    }
  }

  if has_comma {
    parts.push(content.view(start_offset=start, end_offset=content.length()).to_string())
  }
  (parts, has_comma)
}

fn parse_brace_range(content : String) -> Array[String] {
  let parts = split_by_double_dot(content)
  if parts.length() != 2 && parts.length() != 3 {
    return []
  }

  let step_opt = if parts.length() == 3 {
    parse_signed_int(parts[2])
  } else {
    None
  }
  match (parse_signed_int(parts[0]), parse_signed_int(parts[1])) {
    (Some(start_num), Some(end_num)) => {
      let step = match step_opt {
        Some(v) => v
        None => if end_num >= start_num { 1L } else { -1L }
      }
      if step == 0L {
        return []
      }
      return generate_numeric_range(start_num, end_num, step)
    }
    _ => ()
  }

  if parts[0].length() == 1 && parts[1].length() == 1 {
    let start_ch = parts[0][0].to_int()
    let end_ch = parts[1][0].to_int()
    let step_i64 = match step_opt {
      Some(v) => v
      None => if end_ch >= start_ch { 1L } else { -1L }
    }
    if step_i64 == 0L {
      return []
    }
    let step = step_i64.to_int()
    return generate_char_range(start_ch, end_ch, step)
  }

  []
}

fn split_by_double_dot(content : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i + 1 < content.length() {
    if content[i] == '.' && content[i + 1] == '.' {
      parts.push(content.view(start_offset=start, end_offset=i).to_string())
      start = i + 2
      i += 2
      continue
    }
    i += 1
  }
  parts.push(content.view(start_offset=start, end_offset=content.length()).to_string())
  parts
}

fn parse_signed_int(text : String) -> Int64? {
  if text.length() == 0 {
    return None
  }
  let mut sign = 1L
  let mut i = 0
  if text[0] == '-' {
    sign = -1L
    i = 1
  } else if text[0] == '+' {
    i = 1
  }
  if i >= text.length() {
    return None
  }
  let mut value = 0L
  while i < text.length() {
    let ch = text[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10L + (ch.to_int() - '0'.to_int()).to_int64()
    i += 1
  }
  Some(value * sign)
}

fn generate_numeric_range(start_num : Int64, end_num : Int64, step : Int64) -> Array[String] {
  let out : Array[String] = []
  let mut current = start_num
  while true {
    if out.length() >= brace_expansion_result_limit {
      break
    }
    if step > 0L {
      if current > end_num {
        break
      }
    } else if current < end_num {
      break
    }
    out.push(current.to_string())
    current += step
  }
  out
}

fn generate_char_range(start_ch : Int, end_ch : Int, step : Int) -> Array[String] {
  let out : Array[String] = []
  let mut current = start_ch
  while true {
    if out.length() >= brace_expansion_result_limit {
      break
    }
    if step > 0 {
      if current > end_ch {
        break
      }
    } else if current < end_ch {
      break
    }
    let buf = StringBuilder::new()
    buf.write_char(current.unsafe_to_char())
    out.push(buf.to_string())
    current += step
  }
  out
}

// ============================================================================
// Pathname Expansion (Globbing)
// ============================================================================

fn ExecContext::pathname_expand(
  self : ExecContext,
  words : Array[String]
) -> Array[String] {
  if self.options.noglob {
    return words
  }
  let expanded : Array[String] = []
  for word in words {
    if not(has_glob_meta(word)) {
      expanded.push(word)
      continue
    }
    let matches = self.expand_glob_word(word)
    if matches.length() == 0 {
      expanded.push(word)
    } else {
      for m in matches {
        expanded.push(m)
      }
    }
  }
  expanded
}

fn ExecContext::expand_glob_word(
  self : ExecContext,
  pattern : String
) -> Array[String] {
  let absolute_pattern = if pattern.length() > 0 && pattern[0] == '/' {
    try {
      @fs.normalize_path(pattern)
    } catch {
      _ => pattern
    }
  } else {
    try {
      @fs.resolve_path(self.cwd, pattern)
    } catch {
      _ => self.cwd + "/" + pattern
    }
  }
  let segments = split_path_segments(absolute_pattern)
  let absolute_matches : Array[String] = []
  self.glob_expand_segments(segments, 0, "/", absolute_matches)

  let display_matches : Array[String] = []
  for abs_path in absolute_matches {
    if pattern.length() > 0 && pattern[0] == '/' {
      display_matches.push(abs_path)
    } else {
      display_matches.push(self.abs_to_shell_path(abs_path))
    }
  }
  sort_strings(display_matches)
  display_matches
}

fn ExecContext::glob_expand_segments(
  self : ExecContext,
  segments : Array[String],
  idx : Int,
  current_abs : String,
  out : Array[String]
) -> Unit {
  if idx >= segments.length() {
    if not(self.consume_glob_operation()) {
      return
    }
    if self.fs.exists(current_abs) {
      out.push(current_abs)
    }
    return
  }

  let segment = segments[idx]
  if has_glob_meta(segment) {
    if not(self.consume_glob_operation()) {
      return
    }
    let entries = try {
      self.fs.readdir(current_abs)
    } catch {
      @fs.FsError(_msg) => return
    }

    let names : Array[String] = []
    for entry in entries {
      names.push(entry.name)
    }
    sort_strings(names)

    let mut include_dotfiles = false
    if segment.length() > 0 && segment[0] == '.' {
      include_dotfiles = true
    }

    for name in names {
      if not(include_dotfiles) && name.length() > 0 && name[0] == '.' {
        continue
      }
      if not(@fs.glob_match(segment, name)) {
        continue
      }

      let child_abs = if current_abs == "/" {
        "/" + name
      } else {
        current_abs + "/" + name
      }
      if idx + 1 >= segments.length() {
        if not(self.consume_glob_operation()) {
          return
        }
        if self.fs.exists(child_abs) {
          out.push(child_abs)
        }
      } else {
        if not(self.consume_glob_operation()) {
          return
        }
        let stat = try {
          self.fs.stat(child_abs)
        } catch {
          @fs.FsError(_msg) => continue
        }
        if stat.is_directory {
          self.glob_expand_segments(segments, idx + 1, child_abs, out)
        }
      }
    }
    return
  }

  let next_abs = if current_abs == "/" {
    "/" + segment
  } else {
    current_abs + "/" + segment
  }
  if not(self.consume_glob_operation()) {
    return
  }
  if not(self.fs.exists(next_abs)) {
    return
  }
  if idx + 1 >= segments.length() {
    out.push(next_abs)
    return
  }
  if not(self.consume_glob_operation()) {
    return
  }
  let stat = try {
    self.fs.stat(next_abs)
  } catch {
    @fs.FsError(_msg) => return
  }
  if stat.is_directory {
    self.glob_expand_segments(segments, idx + 1, next_abs, out)
  }
}

fn ExecContext::fail_execution_limit(self : ExecContext, message : String) -> Unit {
  if self.exit_code != 126 {
    self.stderr_buf.write_string("moon_bash: \{message}\n")
  }
  self.exit_code = 126
  self.should_exit = true
}

fn ExecContext::consume_glob_operation(self : ExecContext) -> Bool {
  self.glob_operations += 1
  if self.glob_operations > self.limits.max_glob_operations {
    self.fail_execution_limit("Glob operation limit exceeded")
    return false
  }
  true
}

fn expansion_array_count_storage_key(name : String) -> String {
  "__MOON_BASH_ARRAY_COUNT__" + name
}

fn array_count_var_name(name : String) -> String? {
  if name.length() >= 3 {
    let suffix = name.view(start_offset=name.length() - 3, end_offset=name.length()).to_string()
    if suffix == "[@]" || suffix == "[*]" {
      let base = name.view(start_offset=0, end_offset=name.length() - 3).to_string()
      return Some(expansion_array_count_storage_key(base))
    }
  }
  None
}

fn indirection_array_keys_name(name : String) -> String? {
  if name.length() >= 3 {
    let suffix = name.view(start_offset=name.length() - 3, end_offset=name.length()).to_string()
    if suffix == "[@]" || suffix == "[*]" {
      let base = name.view(start_offset=0, end_offset=name.length() - 3).to_string()
      if base.length() > 0 {
        return Some(base)
      }
    }
  }
  None
}

fn indirection_prefix_name(name : String) -> String? {
  if name.length() <= 1 {
    return None
  }
  let last = name[name.length() - 1].to_int().unsafe_to_char()
  if last == '*' || last == '@' {
    let prefix = name.view(start_offset=0, end_offset=name.length() - 1).to_string()
    if prefix.length() > 0 {
      return Some(prefix)
    }
  }
  None
}

fn ExecContext::expand_variables_with_prefix(
  self : ExecContext,
  prefix : String
) -> String {
  let names : Array[String] = []
  for key, _value in self.env {
    if starts_with(key, prefix) {
      names.push(key)
    }
  }
  sort_strings(names)
  names.iter().fold(
    init="",
    fn(acc, name) { if acc.length() == 0 { name } else { acc + " " + name } },
  )
}

fn parse_array_reference_name(name : String) -> (String, String)? {
  if name.length() < 4 || name[name.length() - 1] != ']' {
    return None
  }

  let mut bracket = -1
  for i = 0; i < name.length(); i = i + 1 {
    if name[i] == '[' {
      bracket = i
      break
    }
  }
  if bracket <= 0 {
    return None
  }

  let base = name.view(start_offset=0, end_offset=bracket).to_string()
  if not(is_expand_var_base_name(base)) {
    return None
  }

  let index = name.view(start_offset=bracket + 1, end_offset=name.length() - 1).to_string()
  if index.length() == 0 {
    return None
  }

  Some((base, index))
}

fn is_expand_var_base_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let first = name[0].to_int().unsafe_to_char()
  if not(
    (first >= 'a' && first <= 'z') ||
    (first >= 'A' && first <= 'Z') ||
    first == '_'
  ) {
    return false
  }

  for i = 1; i < name.length(); i = i + 1 {
    let ch = name[i].to_int().unsafe_to_char()
    if not(
      (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_'
    ) {
      return false
    }
  }
  true
}

fn trim_ascii_space_simple(s : String) -> String {
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

  s.view(start_offset=start, end_offset=end_).to_string()
}

fn strip_wrapping_quotes(text : String) -> String {
  if text.length() >= 2 {
    let first = text[0].to_int().unsafe_to_char()
    let last = text[text.length() - 1].to_int().unsafe_to_char()
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return text.view(start_offset=1, end_offset=text.length() - 1).to_string()
    }
  }
  text
}

fn ExecContext::expand_array_keys(self : ExecContext, base : String) -> String {
  let keys = self.collect_array_keys(base)
  keys.iter().fold(
    init="",
    fn(acc, key) { if acc.length() == 0 { key } else { acc + " " + key } },
  )
}

fn ExecContext::collect_array_keys(
  self : ExecContext,
  base : String
) -> Array[String] {
  let keys : Array[String] = []
  let prefix = base + "["
  for env_key, _value in self.env {
    if starts_with(env_key, prefix) && env_key.length() > prefix.length() &&
      env_key[env_key.length() - 1] == ']' {
      let key = env_key.view(start_offset=prefix.length(), end_offset=env_key.length() - 1).to_string()
      if key != "@" && key != "*" {
        keys.push(key)
      }
    }
  }
  sort_array_key_names(keys)
  keys
}

fn sort_array_key_names(keys : Array[String]) -> Unit {
  keys.sort_by(fn(a, b) {
    match (parse_non_negative_array_key(a), parse_non_negative_array_key(b)) {
      (Some(ai), Some(bi)) => {
        if ai < bi {
          -1
        } else if ai > bi {
          1
        } else {
          0
        }
      }
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => compare_array_key_text(a, b)
    }
  })
}

fn parse_non_negative_array_key(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

fn compare_array_key_text(a : String, b : String) -> Int {
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

fn split_path_segments(path : String) -> Array[String] {
  let segments : Array[String] = []
  let mut start = 0
  for i = 0; i <= path.length(); i = i + 1 {
    if i == path.length() || path[i] == '/' {
      if i > start {
        segments.push(path.view(start_offset=start, end_offset=i).to_string())
      }
      start = i + 1
    }
  }
  segments
}

fn has_glob_meta(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '*' || ch == '?' || ch == '[' {
      return true
    }
  }
  false
}

fn word_should_apply_glob(parts : Array[@ast.WordPart]) -> Bool {
  for part in parts {
    match part {
      @ast.WordPart::Literal(s) => {
        if has_glob_meta(s) {
          return true
        }
      }
      @ast.WordPart::Variable(_)
      | @ast.WordPart::ParameterExpansion(_)
      | @ast.WordPart::CommandSubstitution(_)
      | @ast.WordPart::BraceExpansion(_)
      | @ast.WordPart::TildePrefix(_)
      | @ast.WordPart::Glob(_) => {
        // Unquoted expansions may produce glob metacharacters.
        return true
      }
      @ast.WordPart::ArithmeticExpansion(_)
      | @ast.WordPart::SingleQuoted(_)
      | @ast.WordPart::DoubleQuoted(_) => ()
    }
  }
  false
}

fn ExecContext::abs_to_shell_path(self : ExecContext, abs_path : String) -> String {
  if abs_path == self.cwd {
    return "."
  }
  if self.cwd == "/" {
    if abs_path.length() > 0 && abs_path[0] == '/' {
      return abs_path.view(start_offset=1).to_string()
    }
    return abs_path
  }
  let prefix = self.cwd + "/"
  if starts_with(abs_path, prefix) {
    return abs_path.view(start_offset=prefix.length()).to_string()
  }
  abs_path
}

fn starts_with(s : String, prefix : String) -> Bool {
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

fn sort_strings(values : Array[String]) -> Unit {
  values.sort_by(fn(a, b) {
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
  })
}

// ============================================================================
// Pattern Matching Helpers
// ============================================================================

fn strip_prefix_pattern(value : String, pattern : String, greedy : Bool) -> String {
  if pattern.length() == 0 {
    return value
  }
  // Simple literal prefix matching (no glob support yet)
  if greedy {
    // Try longest match from start
    for i = value.length(); i >= 0; i = i - 1 {
      let prefix = value.view(start_offset=0, end_offset=i).to_string()
      if simple_pattern_match(prefix, pattern) {
        return value.view(start_offset=i).to_string()
      }
    }
    value
  } else {
    // Try shortest match from start
    for i = 0; i <= value.length(); i = i + 1 {
      let prefix = value.view(start_offset=0, end_offset=i).to_string()
      if simple_pattern_match(prefix, pattern) {
        return value.view(start_offset=i).to_string()
      }
    }
    value
  }
}

fn strip_suffix_pattern(value : String, pattern : String, greedy : Bool) -> String {
  if pattern.length() == 0 {
    return value
  }
  if greedy {
    // Try longest match from end
    for i = 0; i <= value.length(); i = i + 1 {
      let suffix = value.view(start_offset=i).to_string()
      if simple_pattern_match(suffix, pattern) {
        return value.view(start_offset=0, end_offset=i).to_string()
      }
    }
    value
  } else {
    // Try shortest match from end
    for i = value.length(); i >= 0; i = i - 1 {
      let suffix = value.view(start_offset=i).to_string()
      if simple_pattern_match(suffix, pattern) {
        return value.view(start_offset=0, end_offset=i).to_string()
      }
    }
    value
  }
}

/// Simple pattern matching supporting * and ? globs.
fn simple_pattern_match(s : String, pattern : String) -> Bool {
  match_pattern(s, 0, pattern, 0)
}

fn match_pattern(s : String, si : Int, p : String, pi : Int) -> Bool {
  if pi >= p.length() {
    return si >= s.length()
  }
  let pch = p[pi].to_int().unsafe_to_char()
  if pch == '*' {
    // Try matching zero or more characters
    for i = si; i <= s.length(); i = i + 1 {
      if match_pattern(s, i, p, pi + 1) {
        return true
      }
    }
    return false
  }
  if si >= s.length() {
    return false
  }
  if pch == '?' {
    return match_pattern(s, si + 1, p, pi + 1)
  }
  let sch = s[si].to_int().unsafe_to_char()
  if pch == sch {
    return match_pattern(s, si + 1, p, pi + 1)
  }
  false
}

fn replace_pattern(
  value : String,
  pattern : String,
  replacement : String,
  mode : @ast.ReplaceMode
) -> String {
  if pattern.length() == 0 {
    return value
  }
  match mode {
    @ast.ReplaceMode::First => replace_first(value, pattern, replacement)
    @ast.ReplaceMode::All => replace_all(value, pattern, replacement)
    @ast.ReplaceMode::Prefix => {
      // Replace only if pattern matches at beginning
      for i = 0; i <= value.length(); i = i + 1 {
        let prefix = value.view(start_offset=0, end_offset=i).to_string()
        if simple_pattern_match(prefix, pattern) {
          return replacement + value.view(start_offset=i).to_string()
        }
      }
      value
    }
    @ast.ReplaceMode::Suffix => {
      // Replace only if pattern matches at end
      for i = value.length(); i >= 0; i = i - 1 {
        let suffix = value.view(start_offset=i).to_string()
        if simple_pattern_match(suffix, pattern) {
          return value.view(start_offset=0, end_offset=i).to_string() + replacement
        }
      }
      value
    }
  }
}

fn replace_first(value : String, pattern : String, replacement : String) -> String {
  // Try each position
  for i = 0; i < value.length(); i = i + 1 {
    for j = i + 1; j <= value.length(); j = j + 1 {
      let substr = value.view(start_offset=i, end_offset=j).to_string()
      if simple_pattern_match(substr, pattern) {
        return value.view(start_offset=0, end_offset=i).to_string() + replacement + value.view(start_offset=j).to_string()
      }
    }
  }
  value
}

fn replace_all(value : String, pattern : String, replacement : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < value.length() {
    let mut matched = false
    for j = i + 1; j <= value.length(); j = j + 1 {
      let substr = value.view(start_offset=i, end_offset=j).to_string()
      if simple_pattern_match(substr, pattern) {
        buf.write_string(replacement)
        i = j
        matched = true
        break
      }
    }
    if not(matched) {
      buf.write_char(value[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  buf.to_string()
}

// ============================================================================
// String Case Helpers
// ============================================================================

fn to_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'a' && ch <= 'z' {
      buf.write_char((ch.to_int() - 32).unsafe_to_char())
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

fn to_lower(s : String) -> String {
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

fn upper_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let first = s[0].to_int().unsafe_to_char()
  let upper = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char()
  } else {
    first
  }
  let buf = StringBuilder::new()
  buf.write_char(upper)
  for i = 1; i < s.length(); i = i + 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

fn lower_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let first = s[0].to_int().unsafe_to_char()
  let lower = if first >= 'A' && first <= 'Z' {
    (first.to_int() + 32).unsafe_to_char()
  } else {
    first
  }
  let buf = StringBuilder::new()
  buf.write_char(lower)
  for i = 1; i < s.length(); i = i + 1 {
    buf.write_char(s[i].to_int().unsafe_to_char())
  }
  buf.to_string()
}

// ============================================================================
// Utility
// ============================================================================

fn strip_trailing_newlines(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] == '\n' {
    end -= 1
  }
  s.view(start_offset=0, end_offset=end).to_string()
}

fn int_pow(base : Int64, exp : Int64) -> Int64 {
  if exp <= 0L {
    return 1L
  }
  let mut result = 1L
  for _i = 0; _i < exp.to_int(); _i = _i + 1 {
    result *= base
  }
  result
}
