// Shell interpreter - array/FD helpers and command runner

let command_stub_marker_prefix : String = "# moon_bash command stub:"

fn fd_output_key(fd : Int) -> String {
  "__MOON_BASH_FD_OUT__" + fd.to_string()
}

fn parse_fd_target_number(text : String) -> Int? {
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

fn encode_fd_output_mapping(path : String, append : Bool) -> String {
  if append { "A:" + path } else { "W:" + path }
}

fn decode_fd_output_mapping(spec : String) -> (String, Bool)? {
  if spec.length() < 3 {
    return None
  }
  let mode = spec[0].to_int().unsafe_to_char()
  if spec[1].to_int().unsafe_to_char() != ':' {
    return None
  }
  let path = spec.view(start_offset=2).to_string()
  if mode == 'A' {
    Some((path, true))
  } else if mode == 'W' {
    Some((path, false))
  } else {
    None
  }
}

fn ExecContext::store_fd_output_mapping(
  self : ExecContext,
  fd : Int,
  target : String,
  append : Bool
) -> Unit {
  self.env[fd_output_key(fd)] = encode_fd_output_mapping(target, append)
}

fn ExecContext::load_fd_output_mapping(
  self : ExecContext,
  target : String
) -> (String, Bool)? {
  match parse_fd_target_number(target) {
    Some(fd) => {
      match self.env.get(fd_output_key(fd)) {
        Some(spec) => decode_fd_output_mapping(spec)
        None => None
      }
    }
    None => None
  }
}

fn ExecContext::try_store_array_assignment(
  self : ExecContext,
  name : String,
  raw_value : @ast.Word,
  append : Bool
) -> Bool {
  // Only plain shell names can take compound array literals `(a b c)`.
  if not(is_valid_shell_name(name)) {
    return false
  }

  let items = match split_array_assignment_items(raw_value.parts) {
    Some(parsed) => parsed
    None => return false
  }

  let values : Array[String] = []
  for item_word in items {
    let expanded = self.expand_array_assignment_item_values(item_word)
    for item in expanded {
      values.push(item)
      if values.length() > self.limits.max_array_elements {
        self.fail_execution_limit("array element limit exceeded")
        return true
      }
    }
    if self.should_exit {
      return true
    }
  }
  let is_assoc = self.env.get(test_array_kind_storage_key(name)).unwrap_or("") == "assoc"
  if is_assoc {
    let entries = self.parse_assoc_assignment_entries(name, values)
    self.store_assoc_assignment(name, entries, append)
    return true
  }
  self.store_indexed_assignment(name, values, append)
  true
}

fn ExecContext::expand_array_assignment_item_values(
  self : ExecContext,
  item_word : @ast.Word
) -> Array[String] {
  // `[index]=value` words should keep literal braces and skip word splitting.
  let raw = self.expand_word_to_string(item_word)
  if self.should_exit {
    return []
  }
  match parse_array_assignment_explicit_entry(raw) {
    Some(_) => [raw]
    None => self.expand_word(item_word)
  }
}

fn ExecContext::parse_assoc_assignment_entries(
  self : ExecContext,
  name : String,
  values : Array[String]
) -> Array[(String, String, Bool)] {
  let entries : Array[(String, String, Bool)] = []
  let mut has_explicit = false
  for token in values {
    match parse_array_assignment_explicit_entry(token) {
      Some(_) => {
        has_explicit = true
        break
      }
      None => ()
    }
  }

  if has_explicit {
    for token in values {
      match parse_array_assignment_explicit_entry(token) {
        Some(entry) => entries.push(entry)
        None => {
          self.stderr_buf.write_string(
            "bash: line 2: \{name}: \{token}: must use subscript when assigning associative array\n",
          )
        }
      }
    }
    return entries
  }

  let mut i = 0
  while i < values.length() {
    let token = values[i]
    match parse_array_assignment_explicit_entry(token) {
      Some(entry) => {
        entries.push(entry)
        i += 1
      }
      None => {
        let key = normalize_array_assignment_index(token)
        let value = if i + 1 < values.length() { values[i + 1] } else { "" }
        entries.push((key, value, false))
        i += 2
      }
    }
  }
  entries
}

fn parse_array_assignment_explicit_entry(token : String) -> (String, String, Bool)? {
  if token.length() < 3 {
    return None
  }
  if token[0].to_int().unsafe_to_char() != '[' {
    return None
  }

  let close = match find_array_assignment_close_bracket(token) {
    Some(pos) => pos
    None => return None
  }

  let (value_start, append_mode) = if close + 1 < token.length() &&
    token[close + 1].to_int().unsafe_to_char() == '=' {
      (close + 2, false)
    } else if close + 2 < token.length() &&
      token[close + 1].to_int().unsafe_to_char() == '+' &&
      token[close + 2].to_int().unsafe_to_char() == '=' {
        (close + 3, true)
      } else {
        return None
      }

  let raw_key = token.view(start_offset=1, end_offset=close).to_string()
  let value = token.view(start_offset=value_start).to_string()
  let key = normalize_array_assignment_index(raw_key)
  Some((key, value, append_mode))
}

fn find_array_assignment_close_bracket(token : String) -> Int? {
  let mut depth = 1
  let mut in_single = false
  let mut in_double = false
  let mut escaped = false

  for i = 1; i < token.length(); i = i + 1 {
    let ch = token[i].to_int().unsafe_to_char()
    if escaped {
      escaped = false
      continue
    }

    if in_single {
      if ch == '\'' {
        in_single = false
      }
      continue
    }
    if in_double {
      if ch == '"' {
        in_double = false
      } else if ch == '\\' {
        escaped = true
      }
      continue
    }

    if ch == '\'' {
      in_single = true
      continue
    }
    if ch == '"' {
      in_double = true
      continue
    }
    if ch == '\\' {
      escaped = true
      continue
    }
    if ch == '[' {
      depth += 1
      continue
    }
    if ch == ']' {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
  }
  None
}

fn ExecContext::normalize_compound_assignment_value(
  self : ExecContext,
  value : String
) -> String {
  if value.length() == 0 {
    return value
  }

  let home = self.env.get("HOME").unwrap_or("/home/user")
  let out = StringBuilder::new()
  let mut segment_start = 0
  let mut i = 0
  while i <= value.length() {
    if i == value.length() || value[i].to_int().unsafe_to_char() == ':' {
      let segment = value.view(start_offset=segment_start, end_offset=i).to_string()
      let normalized = if segment == "~" {
        home
      } else if segment.length() >= 2 &&
        segment[0].to_int().unsafe_to_char() == '~' &&
        segment[1].to_int().unsafe_to_char() == '/' {
          home + segment.view(start_offset=1).to_string()
        } else {
          segment
        }
      out.write_string(normalized)
      if i < value.length() {
        out.write_char(':')
      }
      segment_start = i + 1
    }
    i += 1
  }
  out.to_string()
}

fn ExecContext::store_assoc_assignment(
  self : ExecContext,
  name : String,
  entries : Array[(String, String, Bool)],
  append : Bool
) -> Unit {
  if not(append) {
    self.store_array_assignment(name, [])
  }

  for entry in entries {
    let (key, value, append_mode) = entry
    let storage_key = "\{name}[\{key}]"
    let normalized = self.normalize_compound_assignment_value(value)
    if append_mode {
      self.env[storage_key] = self.env.get(storage_key).unwrap_or("") + normalized
    } else {
      self.env[storage_key] = normalized
    }
  }
  self.refresh_array_metadata(name)
  self.env[test_array_kind_storage_key(name)] = "assoc"
}

fn ExecContext::next_indexed_assignment_seed(
  self : ExecContext,
  name : String,
  append : Bool
) -> Int {
  if not(append) {
    return 0
  }

  let keys = self.collect_array_keys(name)
  let mut seed = 0
  for key in keys {
    match parse_non_negative_int_for_sort(key) {
      Some(idx) => {
        if idx + 1 > seed {
          seed = idx + 1
        }
      }
      None => ()
    }
  }
  seed
}

fn ExecContext::parse_indexed_assignment_index(
  self : ExecContext,
  raw_index : String
) -> Int {
  match parse_array_reference_name(raw_index) {
    Some((base, index_expr)) => {
      let resolved = self.expand_array_element_reference(base, index_expr)
      if self.should_exit {
        return 0
      }
      let next_raw = if resolved.length() > 0 { resolved } else { "0" }
      if next_raw != raw_index {
        return self.parse_indexed_assignment_index(next_raw)
      }
    }
    None => ()
  }

  match parse_non_negative_int_for_sort(raw_index) {
    Some(idx) => idx
    None => {
      let evaluated = self.eval_arith(@ast.ArithExpr::Raw(raw_index))
      if evaluated <= 0L {
        0
      } else if evaluated > 2147483647L {
        2147483647
      } else {
        evaluated.to_int()
      }
    }
  }
}

fn ExecContext::store_indexed_assignment(
  self : ExecContext,
  name : String,
  values : Array[String],
  append : Bool
) -> Unit {
  if not(append) {
    self.store_array_assignment(name, [])
  }
  let mut next_index = self.next_indexed_assignment_seed(name, append)
  for token in values {
    match parse_array_assignment_explicit_entry(token) {
      Some((raw_index, value, append_mode)) => {
        let index = self.parse_indexed_assignment_index(raw_index)
        let storage_key = "\{name}[\{index.to_string()}]"
        let normalized = self.normalize_compound_assignment_value(value)
        if append_mode {
          self.env[storage_key] = self.env.get(storage_key).unwrap_or("") + normalized
        } else {
          self.env[storage_key] = normalized
        }
        next_index = index + 1
      }
      None => {
        let storage_key = "\{name}[\{next_index.to_string()}]"
        let normalized = self.normalize_compound_assignment_value(token)
        self.env[storage_key] = normalized
        next_index += 1
      }
    }
  }
  self.refresh_array_metadata(name)
  self.env[test_array_kind_storage_key(name)] = "indexed"
}

fn collect_assignment_restore_names(
  assignments : Array[@ast.Assignment]
) -> Array[String] {
  let names : Array[String] = []
  for assign in assignments {
    let name = assignment_restore_base_name(assign.name)
    let mut exists = false
    for existing in names {
      if existing == name {
        exists = true
        break
      }
    }
    if not(exists) {
      names.push(name)
    }
  }
  names
}

fn assignment_restore_base_name(raw_name : String) -> String {
  match parse_array_element_assignment_name(raw_name) {
    Some((base, _index)) => base
    None => raw_name
  }
}

fn snapshot_assignment_env_entries(
  env : Map[String, String],
  names : Array[String]
) -> Map[String, String] {
  let snapshot : Map[String, String] = {}
  for key, value in env {
    if env_key_matches_assignment_restore_names(key, names) {
      snapshot[key] = value
    }
  }
  snapshot
}

fn restore_assignment_env_entries(
  env : Map[String, String],
  names : Array[String],
  snapshot : Map[String, String]
) -> Unit {
  let to_remove : Array[String] = []
  for key, _value in env {
    if env_key_matches_assignment_restore_names(key, names) {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    env.remove(key)
  }
  for key, value in snapshot {
    env[key] = value
  }
}

fn env_key_matches_assignment_restore_names(
  key : String,
  names : Array[String]
) -> Bool {
  for name in names {
    if env_key_matches_assignment_restore_name(key, name) {
      return true
    }
  }
  false
}

fn env_key_matches_assignment_restore_name(key : String, name : String) -> Bool {
  if key == name ||
    key == test_array_count_storage_key(name) ||
    key == test_array_kind_storage_key(name) {
    return true
  }
  string_has_prefix(key, name + "[")
}

fn command_keeps_prefix_assignments(cmd_name : String) -> Bool {
  cmd_name == "declare" ||
  cmd_name == "typeset" ||
  cmd_name == "local" ||
  cmd_name == "export" ||
  cmd_name == "readonly"
}

fn split_array_assignment_items(
  parts : Array[@ast.WordPart]
) -> Array[@ast.Word]? {
  let items : Array[@ast.Word] = []
  let mut current_parts : Array[@ast.WordPart] = []
  let literal_buf = StringBuilder::new()
  let mut started = false
  let mut ended = false

  for part in parts {
    match part {
      @ast.WordPart::Literal(text) => {
        for i = 0; i < text.length(); i = i + 1 {
          let ch = text[i].to_int().unsafe_to_char()
          if not(started) {
            if array_assignment_is_space(ch) {
              continue
            }
            if ch == '(' {
              started = true
              continue
            }
            return None
          }

          if ended {
            if array_assignment_is_space(ch) {
              continue
            }
            return None
          }

          if ch == ')' {
            split_array_assignment_flush_literal(current_parts, literal_buf)
            if current_parts.length() > 0 {
              items.push({ parts: current_parts })
              current_parts = []
            }
            ended = true
            continue
          }

          if array_assignment_is_space(ch) {
            split_array_assignment_flush_literal(current_parts, literal_buf)
            if current_parts.length() > 0 {
              items.push({ parts: current_parts })
              current_parts = []
            }
            continue
          }

          literal_buf.write_char(ch)
        }
      }
      _ => {
        if not(started) || ended {
          return None
        }
        split_array_assignment_flush_literal(current_parts, literal_buf)
        current_parts.push(part)
      }
    }
  }

  if not(started) || not(ended) {
    return None
  }
  if current_parts.length() > 0 || literal_buf.to_string().length() > 0 {
    return None
  }

  Some(items)
}

fn split_array_assignment_flush_literal(
  current_parts : Array[@ast.WordPart],
  literal_buf : StringBuilder
) -> Unit {
  let lit = literal_buf.to_string()
  if lit.length() > 0 {
    current_parts.push(@ast.WordPart::Literal(lit))
    literal_buf.reset()
  }
}

fn array_assignment_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n'
}

fn ExecContext::store_array_assignment(
  self : ExecContext,
  name : String,
  values : Array[String]
) -> Unit {
  let count_key = "__MOON_BASH_ARRAY_COUNT__" + name
  let index_prefix = name + "["
  let keys_to_remove : Array[String] = []
  for key, _value in self.env {
    if key == count_key ||
      key == name + "[@]" ||
      key == name + "[*]" ||
      string_has_prefix(key, index_prefix) {
      keys_to_remove.push(key)
    }
  }
  for key in keys_to_remove {
    self.env.remove(key)
  }

  let joined = join_values_for_array_storage(values)
  self.env[name] = if values.length() > 0 { values[0] } else { "" }
  self.env[name + "[@]"] = joined
  self.env[name + "[*]"] = joined
  self.env[count_key] = values.length().to_string()
  for i = 0; i < values.length(); i = i + 1 {
    self.env["\{name}[\{i.to_string()}]"] = values[i]
  }
}

fn ExecContext::store_array_element_assignment(
  self : ExecContext,
  base : String,
  index : String,
  value : String,
  append : Bool
) -> Unit {
  if self.env.contains(readonly_storage_key(base)) {
    self.stderr_buf.write_string("moon_bash: \{base}: readonly variable\n")
    self.exit_code = 1
    self.should_exit = true
    return
  }
  let key = "\{base}[\{index}]"
  if append {
    let existing = self.env.get(key).unwrap_or("")
    self.env[key] = existing + value
  } else {
    self.env[key] = value
  }
  self.refresh_array_metadata(base)
}

fn ExecContext::refresh_array_metadata(self : ExecContext, name : String) -> Unit {
  let prefix = name + "["
  let count_key = "__MOON_BASH_ARRAY_COUNT__" + name
  let keys : Array[String] = []

  for key, _value in self.env {
    if key == name + "[@]" || key == name + "[*]" {
      continue
    }
    if string_has_prefix(key, prefix) && key.length() > prefix.length() &&
      key[key.length() - 1] == ']' {
      let inner = key.view(start_offset=prefix.length(), end_offset=key.length() - 1).to_string()
      if inner != "@" && inner != "*" {
        keys.push(inner)
      }
    }
  }

  sort_array_keys(keys)

  let values : Array[String] = []
  for inner in keys {
    let key = "\{name}[\{inner}]"
    values.push(self.env.get(key).unwrap_or(""))
  }

  let joined = join_values_for_array_storage(values)
  self.env[name + "[@]"] = joined
  self.env[name + "[*]"] = joined
  self.env[count_key] = values.length().to_string()
  self.env[name] = self.env.get(name + "[0]").unwrap_or("")
}

fn join_values_for_array_storage(values : Array[String]) -> String {
  let out = StringBuilder::new()
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(values[i])
  }
  out.to_string()
}

fn string_has_prefix(s : String, prefix : String) -> Bool {
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

fn parse_array_element_assignment_name(name : String) -> (String, String)? {
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
  if not(is_valid_shell_name(base)) {
    return None
  }

  let raw_index = name.view(start_offset=bracket + 1, end_offset=name.length() - 1).to_string()
  let index = normalize_array_assignment_index(raw_index)
  if index.length() == 0 {
    return None
  }

  Some((base, index))
}

fn normalize_array_assignment_index(raw_index : String) -> String {
  let trimmed = trim_ascii_space_for_array_index(raw_index)
  let cleaned = strip_array_assignment_index_markers(trimmed)
  if cleaned.length() >= 2 {
    let first = cleaned[0].to_int().unsafe_to_char()
    let last = cleaned[cleaned.length() - 1].to_int().unsafe_to_char()
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return cleaned.view(start_offset=1, end_offset=cleaned.length() - 1).to_string()
    }
  }
  cleaned
}

fn trim_ascii_space_for_array_index(s : String) -> String {
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

fn strip_array_assignment_index_markers(s : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\u0001' && i + 1 < s.length() {
      out.write_char(s[i + 1].to_int().unsafe_to_char())
      i += 2
      continue
    }
    if ch == '\u0002' || ch == '\u0003' {
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn is_valid_shell_name(name : String) -> Bool {
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

fn parse_non_negative_int_for_sort(text : String) -> Int? {
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

fn ExecContext::indexed_array_origin(self : ExecContext, name : String) -> Int64 {
  let keys = self.collect_array_keys(name)
  let mut max_index = -1
  for key in keys {
    match parse_non_negative_int_for_sort(key) {
      Some(idx) => {
        if idx > max_index {
          max_index = idx
        }
      }
      None => ()
    }
  }
  if max_index < 0 {
    0L
  } else {
    max_index.to_int64() + 1L
  }
}

fn compare_text(a : String, b : String) -> Int {
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

fn sort_array_keys(keys : Array[String]) -> Unit {
  keys.sort_by(fn(a, b) {
    match (parse_non_negative_int_for_sort(a), parse_non_negative_int_for_sort(b)) {
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
      (None, None) => compare_text(a, b)
    }
  })
}

fn ExecContext::enforce_output_size_limit(self : ExecContext) -> Unit {
  if self.should_exit {
    return
  }
  let output = self.stdout_buf.to_string()
  if output.length() > self.limits.max_string_length {
    self.fail_execution_limit("output limit exceeded")
  }
}

fn snapshot_array_env_entries(
  env : Map[String, String],
  name : String
) -> Map[String, String] {
  let saved : Map[String, String] = {}
  let prefix = name + "["
  let count_key = "__MOON_BASH_ARRAY_COUNT__" + name
  for key, value in env {
    if key == name ||
      key == name + "[@]" ||
      key == name + "[*]" ||
      key == count_key ||
      string_has_prefix(key, prefix) {
      saved[key] = value
    }
  }
  saved
}

fn ExecContext::restore_array_env_entries(
  self : ExecContext,
  name : String,
  saved : Map[String, String]
) -> Unit {
  let prefix = name + "["
  let count_key = "__MOON_BASH_ARRAY_COUNT__" + name
  let to_remove : Array[String] = []
  for key, _value in self.env {
    if key == name ||
      key == name + "[@]" ||
      key == name + "[*]" ||
      key == count_key ||
      string_has_prefix(key, prefix) {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.env.remove(key)
  }
  for key, value in saved {
    self.env[key] = value
  }
}

fn ExecContext::collect_array_values(self : ExecContext, name : String) -> Array[String] {
  let keys = self.collect_array_keys(name)
  let values : Array[String] = []
  for key in keys {
    values.push(self.env.get("\{name}[\{key}]").unwrap_or(""))
  }
  values
}

// ============================================================================
// Command Dispatch
// ============================================================================

fn is_virtual_command_stub_content(content : String) -> Bool {
  content.length() == 0 || string_has_prefix(content, command_stub_marker_prefix)
}

fn ExecContext::run_virtual_command(
  self : ExecContext,
  name : String,
  args : Array[String]
) -> Bool {
  if self.run_builtin(name, args) {
    self.remember_hashed_command(name)
    return true
  }

  match @commands.find_command(name) {
    Some(cmd_fn) => {
      let ctx : @commands.CommandContext = {
        args,
        stdin_content: self.stdin_buf,
        cwd: self.cwd,
        env: self.env,
        fs: self.fs,
      }
      let result = cmd_fn(ctx)
      self.stdout_buf.write_string(result.stdout)
      self.stderr_buf.write_string(result.stderr)
      self.exit_code = result.exit_code
      self.remember_hashed_command(name)
      true
    }
    None => false
  }
}

fn ExecContext::try_dispatch_virtual_command_stub(
  self : ExecContext,
  resolved_path : String,
  args : Array[String]
) -> Bool {
  let parent = @fs.parent_path(resolved_path)
  if parent != "/bin" && parent != "/usr/bin" {
    return false
  }

  match self.fs.entries.get(resolved_path) {
    Some(@fs.FsEntry::File(data)) => {
      if not(is_virtual_command_stub_content(data.content)) {
        return false
      }
      let name = @fs.basename(resolved_path)
      self.run_virtual_command(name, args)
    }
    _ => false
  }
}

fn ExecContext::execute_script_file_command(
  self : ExecContext,
  resolved_path : String,
  args : Array[String],
  display_name : String
) -> Unit {
  let content = try {
    self.fs.read_file(resolved_path)
  } catch {
    @fs.FsError(msg) => {
      self.stderr_buf.write_string("moon_bash: \{display_name}: \{msg}\n")
      self.exit_code = 126
      return
    }
  }
  let parsed = try {
    @parser.parse(content)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moon_bash: \{display_name}: \{msg}\n")
      self.exit_code = 2
      return
    }
  }

  let saved_count = parse_int32_str(self.env.get("#").unwrap_or("0"))
  let saved_values : Array[String] = []
  for i = 1; i <= saved_count; i = i + 1 {
    saved_values.push(self.env.get(i.to_string()).unwrap_or(""))
  }

  self.set_positional_parameters(args)
  self.execute_script(parsed)
  self.set_positional_parameters(saved_values)
}

fn ExecContext::try_execute_resolved_path_command(
  self : ExecContext,
  original_name : String,
  resolved_path : String,
  args : Array[String]
) -> Bool {
  if self.try_dispatch_virtual_command_stub(resolved_path, args) {
    return true
  }
  match self.fs.entries.get(resolved_path) {
    Some(entry) => {
      match entry {
        @fs.FsEntry::Directory(_) => false
        _ => {
          if not(command_is_executable_entry(entry)) {
            false
          } else {
            self.execute_script_file_command(resolved_path, args, original_name)
            true
          }
        }
      }
    }
    None => false
  }
}

fn ExecContext::run_explicit_path_command(
  self : ExecContext,
  original_name : String,
  args : Array[String]
) -> Unit {
  let resolved_path = try {
    @fs.resolve_path(self.cwd, original_name)
  } catch {
    _ => {
      self.stderr_buf.write_string("moon_bash: \{original_name}: command not found\n")
      self.exit_code = 127
      return
    }
  }

  match self.fs.entries.get(resolved_path) {
    Some(@fs.FsEntry::Directory(_)) => {
      self.stderr_buf.write_string("moon_bash: \{original_name}: Is a directory\n")
      self.exit_code = 126
      return
    }
    Some(entry) => {
      if self.try_dispatch_virtual_command_stub(resolved_path, args) {
        return
      }
      if not(command_is_executable_entry(entry)) {
        self.stderr_buf.write_string("moon_bash: \{original_name}: Permission denied\n")
        self.exit_code = 126
        return
      }
      self.execute_script_file_command(resolved_path, args, original_name)
      return
    }
    None => ()
  }

  let parent = @fs.parent_path(resolved_path)
  if parent == "/bin" || parent == "/usr/bin" {
    let basename = @fs.basename(resolved_path)
    if command_has_virtual_external(basename) || is_lookup_shell_builtin(basename) {
      let saved_skip = self.env.get(command_skip_function_lookup_key)
      self.env[command_skip_function_lookup_key] = "1"
      self.run_command(basename, args)
      match saved_skip {
        Some(value) => self.env[command_skip_function_lookup_key] = value
        None => self.env.remove(command_skip_function_lookup_key)
      }
      return
    }
  }

  self.stderr_buf.write_string("moon_bash: \{original_name}: command not found\n")
  self.exit_code = 127
}

fn ExecContext::run_command(
  self : ExecContext,
  name : String,
  args : Array[String]
) -> Unit {
  let original_name = name
  let dispatch_name = name
  let skip_functions = self.skip_function_lookup_enabled()
  let use_default_path = self.default_path_lookup_enabled()

  if contains_slash(dispatch_name) {
    self.run_explicit_path_command(original_name, args)
    return
  }

  // 1. Check functions (unless command/builtin explicitly disabled function lookup).
  if not(skip_functions) {
    match self.functions.get(dispatch_name) {
      Some(fndef) => {
        self.call_depth += 1
        if self.call_depth > self.limits.max_call_depth {
          self.fail_execution_limit("maximum recursion depth exceeded")
          self.call_depth -= 1
          return
        }
        let saved_funcname_entries = snapshot_array_env_entries(self.env, "FUNCNAME")
        let previous_func_stack = self.collect_array_values("FUNCNAME")
        let current_func_stack : Array[String] = [dispatch_name]
        for fn_name in previous_func_stack {
          current_func_stack.push(fn_name)
        }
        self.store_array_assignment("FUNCNAME", current_func_stack)
        // Save positional params
        let saved_args = self.env.get("@").unwrap_or("")
        let saved_argc = self.env.get("#").unwrap_or("")
        self.env["@"] = args.iter().fold(
          init="",
          fn(acc, a) { if acc.length() == 0 { a } else { acc + " " + a } },
        )
        self.env["#"] = args.length().to_string()
        for i = 0; i < args.length(); i = i + 1 {
          self.env[(i + 1).to_string()] = args[i]
        }
        // Execute function body
        match fndef.body {
          @ast.CompoundCommand::Group(script) => self.execute_script(script)
          other => self.execute_compound(other)
        }
        self.return_requested = false
        self.restore_local_bindings(self.call_depth)
        // Restore
        self.env["@"] = saved_args
        self.env["#"] = saved_argc
        self.restore_array_env_entries("FUNCNAME", saved_funcname_entries)
        self.call_depth -= 1
        return
      }
      None => ()
    }
  }

  // 2. Optional command allowlist
  if not(self.command_allowed(dispatch_name)) {
    self.stderr_buf.write_string("moon_bash: \{original_name}: command not found\n")
    self.exit_code = 127
    return
  }

  // 3. Handle cd specially (needs to modify cwd)
  if dispatch_name == "cd" {
    let target = if args.length() == 0 {
      self.env.get("HOME").unwrap_or("/home/user")
    } else if args[0] == "-" {
      self.env.get("OLDPWD").unwrap_or(self.cwd)
    } else {
      args[0]
    }
    let resolved = try {
      @fs.resolve_path(self.cwd, target)
    } catch {
      _ => {
        self.stderr_buf.write_string("cd: No such file or directory: \{target}\n")
        self.exit_code = 1
        return
      }
    }
    match self.fs.entries.get(resolved) {
      Some(@fs.FsEntry::Directory(_)) => {
        let old_pwd = self.cwd
        self.cwd = resolved
        self.env["PWD"] = resolved
        self.env["OLDPWD"] = old_pwd
        self.sync_directory_stack_with_cwd()
        self.remember_hashed_command(dispatch_name)
        self.exit_code = 0
      }
      Some(_) => {
        self.stderr_buf.write_string("cd: Not a directory: \{target}\n")
        self.exit_code = 1
      }
      None => {
        self.stderr_buf.write_string("cd: No such file or directory: \{target}\n")
        self.exit_code = 1
      }
    }
    return
  }

  // 4. Real shell builtins have higher precedence than PATH.
  if is_lookup_shell_builtin(dispatch_name) {
    if self.run_virtual_command(dispatch_name, args) {
      return
    }
  }

  // 5. Check hashed path entries unless command -p forced default PATH.
  if not(use_default_path) {
    match self.lookup_hashed_command_path(dispatch_name) {
      Some(hashed_path) => {
        if self.try_execute_resolved_path_command(
          original_name,
          hashed_path,
          args,
        ) {
          return
        }
        self.clear_hashed_command(dispatch_name)
      }
      None => ()
    }
  }

  // 6. Check PATH for executable files.
  match self.first_path_command_match(dispatch_name, use_default_path, false) {
    Some((_display, resolved_path, _is_virtual)) => {
      if self.try_execute_resolved_path_command(original_name, resolved_path, args) {
        self.remember_hashed_command_path(dispatch_name, resolved_path)
        return
      }
    }
    None => ()
  }

  // 7. Fallback to in-kernel virtual commands (builtin + command registry).
  if self.run_virtual_command(dispatch_name, args) {
    return
  }

  // 8. Command not found
  self.stderr_buf.write_string("moon_bash: \{original_name}: command not found\n")
  self.exit_code = 127
}

fn contains_slash(name : String) -> Bool {
  for i = 0; i < name.length(); i = i + 1 {
    if name[i].to_int().unsafe_to_char() == '/' {
      return true
    }
  }
  false
}

fn ExecContext::apply_errexit_after_pipeline(
  self : ExecContext,
  pipeline : @ast.Pipeline,
  next_op : Int?
) -> Unit {
  if self.should_exit || not(self.options.errexit) || self.exit_code == 0 {
    return
  }
  if pipeline.negated {
    return
  }
  match next_op {
    Some(op) => {
      if op == 1 || op == 2 {
        return
      }
    }
    None => ()
  }
  self.should_exit = true
}

fn ExecContext::command_allowed(self : ExecContext, name : String) -> Bool {
  match self.env.get("__MOON_BASH_ALLOWED_COMMANDS") {
    None => true
    Some(spec) => {
      if spec.length() == 0 {
        return false
      }
      let allowed = split_string_by_delimiter(spec, ",")
      for i = 0; i < allowed.length(); i = i + 1 {
        if allowed[i] == name {
          return true
        }
      }
      false
    }
  }
}

fn ExecContext::apply_redirections(
  self : ExecContext,
  redirs : Array[@ast.Redirection],
  _saved_stdout : StringBuilder,
  _saved_stderr : StringBuilder
) -> Unit {
  for redir in redirs {
    match redir.op {
      @ast.RedirectOp::Input => {
        let target = self.expand_word_to_string(redir.target)
        let resolved = try {
          @fs.resolve_path(self.cwd, target)
        } catch {
          _ => target
        }
        let content = try {
          self.fs.read_file(resolved)
        } catch {
          @fs.FsError(_msg) => ""
        }
        self.stdin_buf = content
      }
      @ast.RedirectOp::HereString => {
        let content = self.expand_word_to_string(redir.target)
        self.stdin_buf = content + "\n"
      }
      @ast.RedirectOp::HereDoc(_strip_tabs) => {
        let content = self.expand_word_to_string(redir.target)
        self.stdin_buf = content
      }
      @ast.RedirectOp::Output => {
        let target = self.expand_word_to_string(redir.target)
        if target == "/dev/null" {
          self.stdout_buf = StringBuilder::new()
        }
      }
      _ => ()
    }
  }
}
