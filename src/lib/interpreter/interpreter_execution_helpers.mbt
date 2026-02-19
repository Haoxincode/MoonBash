// Shell interpreter - array/FD helpers and command runner

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
  let items = match split_array_assignment_items(raw_value.parts) {
    Some(parsed) => parsed
    None => return false
  }

  let values : Array[String] = []
  for item_word in items {
    let expanded = self.expand_word(item_word)
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
  if append {
    let merged : Array[String] = []
    let existing = self.expand_array_elements_for_words(name)
    for existing_value in existing {
      merged.push(existing_value)
      if merged.length() > self.limits.max_array_elements {
        self.fail_execution_limit("array element limit exceeded")
        return true
      }
    }
    for value in values {
      merged.push(value)
      if merged.length() > self.limits.max_array_elements {
        self.fail_execution_limit("array element limit exceeded")
        return true
      }
    }
    self.store_array_assignment(name, merged)
  } else {
    self.store_array_assignment(name, values)
  }
  true
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

  let joined = values.iter().fold(
    init="",
    fn(acc, value) { if acc.length() == 0 { value } else { acc + " " + value } },
  )
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

  let joined = values.iter().fold(
    init="",
    fn(acc, v) { if acc.length() == 0 { v } else { acc + " " + v } },
  )
  self.env[name + "[@]"] = joined
  self.env[name + "[*]"] = joined
  self.env[count_key] = values.length().to_string()
  self.env[name] = self.env.get(name + "[0]").unwrap_or("")
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

fn ExecContext::run_command(
  self : ExecContext,
  name : String,
  args : Array[String]
) -> Unit {
  let original_name = name
  let mut dispatch_name = name

  // Support path-style command invocation (/bin/echo) by resolving to basename.
  if contains_slash(name) {
    let resolved_path = try {
      @fs.resolve_path(self.cwd, name)
    } catch {
      _ => name
    }
    match self.fs.entries.get(resolved_path) {
      Some(@fs.FsEntry::File(_)) | Some(@fs.FsEntry::Symlink(_)) =>
        dispatch_name = @fs.basename(resolved_path)
      Some(@fs.FsEntry::Directory(_)) => {
        self.stderr_buf.write_string("moon_bash: \{original_name}: Is a directory\n")
        self.exit_code = 126
        return
      }
      None => {
        self.stderr_buf.write_string("moon_bash: \{original_name}: command not found\n")
        self.exit_code = 127
        return
      }
    }
  }

  // 1. Check functions
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

  // 2. Optional command allowlist
  if not(self.command_allowed(dispatch_name)) {
    self.stderr_buf.write_string("moon_bash: \{original_name}: command not found\n")
    self.exit_code = 127
    return
  }

  // 2. Handle cd specially (needs to modify cwd)
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

  // 3. Check builtins
  if self.run_builtin(dispatch_name, args) {
    return
  }

  // 4. Check command registry
  match @commands.find_command(dispatch_name) {
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
      return
    }
    None => ()
  }

  // 5. Command not found
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
