// moon_bash Interpreter - Word Expansion
// Handles variable expansion, command substitution, word splitting, etc.

// ============================================================================
// Word Expansion
// ============================================================================

/// Expand a Word into an array of strings (after word splitting).
fn ExecContext::expand_word(self : ExecContext, word : @ast.Word) -> Array[String] {
  self.expand_word_internal(word, true)
}

/// Expand a word but skip pathname expansion (used for commands that should
/// receive literal glob patterns such as `find -name "*.txt"`).
fn ExecContext::expand_word_no_glob(
  self : ExecContext,
  word : @ast.Word
) -> Array[String] {
  self.expand_word_internal(word, false)
}

fn ExecContext::expand_word_internal(
  self : ExecContext,
  word : @ast.Word,
  allow_glob : Bool
) -> Array[String] {
  match self.expand_double_quoted_array_words(word.parts) {
    Some(values) => return values
    None => ()
  }

  let expanded_candidates = self.expand_word_parts_with_brace(word.parts)
  if expanded_candidates.length() == 0 {
    return [""]
  }
  if self.should_exit {
    return [""]
  }
  // Word splitting only applies after expansions. Pure literal words
  // (including quoted/escaped literals that become a single token) must
  // remain a single argument.
  let mut has_splittable_expansion = false
  for part in word.parts {
    match part {
      @ast.WordPart::Variable(_)
      | @ast.WordPart::ParameterExpansion(_)
      | @ast.WordPart::CommandSubstitution(_)
      | @ast.WordPart::ArithmeticExpansion(_) => {
        has_splittable_expansion = true
        break
      }
      _ => ()
    }
  }

  let parts : Array[String] = []
  if not(has_splittable_expansion) {
    for candidate in expanded_candidates {
      parts.push(candidate)
    }
  } else {
    for candidate in expanded_candidates {
      let split_parts = self.word_split(candidate)
      for split_part in split_parts {
        parts.push(split_part)
      }
    }
  }
  if parts.length() == 0 {
    return [""]
  }
  if allow_glob && word_should_apply_glob(word.parts) {
    self.pathname_expand(parts)
  } else {
    parts
  }
}

fn ExecContext::expand_double_quoted_array_words(
  self : ExecContext,
  parts : Array[@ast.WordPart]
) -> Array[String]? {
  if parts.length() != 1 {
    return None
  }

  let inner_parts = match parts[0] {
    @ast.WordPart::DoubleQuoted(inner) => inner
    _ => return None
  }
  if inner_parts.length() != 1 {
    return None
  }

  if is_positional_at_expansion(inner_parts[0]) {
    return Some(self.expand_positional_parameters_for_words())
  }

  let (base, expand_keys) = match array_reference_base_for_at(inner_parts[0]) {
    Some(pair) => pair
    None => return None
  }
  if expand_keys {
    Some(self.collect_array_keys(base))
  } else {
    Some(self.expand_array_elements_for_words(base))
  }
}

fn is_positional_at_expansion(part : @ast.WordPart) -> Bool {
  match part {
    @ast.WordPart::Variable(name) => name == "@"
    @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(name)) =>
      name == "@"
    _ => false
  }
}

fn array_reference_base_for_at(part : @ast.WordPart) -> (String, Bool)? {
  let name = match part {
    @ast.WordPart::Variable(raw) => raw
    @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(raw)) => raw
    @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Indirection(raw)) => {
      match indirection_array_keys_name(raw) {
        Some(base) => return Some((base, true))
        None => return None
      }
    }
    _ => return None
  }
  match parse_array_reference_name(name) {
    Some((base, index)) => if index == "@" { Some((base, false)) } else { None }
    None => None
  }
}

fn ExecContext::expand_positional_parameters_for_words(
  self : ExecContext
) -> Array[String] {
  let count = match self.env.get("#") {
    Some(raw) => parse_int32_str(raw)
    None => 0
  }
  let values : Array[String] = []
  for i = 1; i <= count; i = i + 1 {
    values.push(self.env.get(i.to_string()).unwrap_or(""))
  }
  values
}

fn ExecContext::expand_array_elements_for_words(
  self : ExecContext,
  base : String
) -> Array[String] {
  let keys = self.collect_array_keys(base)
  let values : Array[String] = []
  for key in keys {
    values.push(self.env.get("\{base}[\{key}]").unwrap_or(""))
  }
  if values.length() == 0 {
    let count_key = "__MOON_BASH_ARRAY_COUNT__" + base
    if self.env.contains(count_key) {
      return values
    }
    if self.env.contains(base) {
      values.push(self.env.get(base).unwrap_or(""))
    }
  }
  values
}

/// Expand word parts into a single string (no word splitting).
fn ExecContext::expand_word_parts(
  self : ExecContext,
  parts : Array[@ast.WordPart]
) -> String {
  let buf = StringBuilder::new()
  for part in parts {
    buf.write_string(self.expand_word_part(part))
  }
  buf.to_string()
}

fn ExecContext::expand_word_parts_with_brace(
  self : ExecContext,
  parts : Array[@ast.WordPart]
) -> Array[String] {
  let mut expanded : Array[String] = [""]
  for part in parts {
    let part_options : Array[String] = match part {
      @ast.WordPart::Literal(s) => expand_brace_literal(s)
      _ => [self.expand_word_part(part)]
    }

    let next_expanded : Array[String] = []
    for prefix in expanded {
      for option in part_options {
        let combined = prefix + option
        if combined.length() > self.limits.max_string_length {
          self.fail_execution_limit("string length limit exceeded")
          return [""]
        }
        next_expanded.push(combined)
      }
    }
    expanded = next_expanded
  }
  expanded
}

/// Expand a Word to a single string (convenience method).
fn ExecContext::expand_word_to_string(
  self : ExecContext,
  word : @ast.Word
) -> String {
  self.expand_word_parts(word.parts)
}

/// Expand a single WordPart into a string.
fn ExecContext::expand_word_part(
  self : ExecContext,
  part : @ast.WordPart
) -> String {
  match part {
    @ast.WordPart::Literal(s) => s
    @ast.WordPart::SingleQuoted(s) => s
    @ast.WordPart::DoubleQuoted(inner_parts) => {
      let buf = StringBuilder::new()
      for p in inner_parts {
        buf.write_string(self.expand_word_part(p))
      }
      buf.to_string()
    }
    @ast.WordPart::Variable(name) => self.expand_variable(name)
    @ast.WordPart::ParameterExpansion(pe) => self.expand_param(pe)
    @ast.WordPart::CommandSubstitution(script_str) =>
      self.expand_command_sub(script_str)
    @ast.WordPart::TildePrefix(user) => self.expand_tilde(user)
    @ast.WordPart::ArithmeticExpansion(expr) =>
      self.eval_arith(expr).to_string()
    @ast.WordPart::BraceExpansion(_) => ""
    @ast.WordPart::Glob(_) => ""
  }
}

// ============================================================================
// Variable Expansion
// ============================================================================

fn ExecContext::expand_variable(self : ExecContext, name : String) -> String {
  match name {
    "?" => self.exit_code.to_string()
    "$" => "1" // Simulated PID
    "#" => self.env.get("#").unwrap_or("0")
    "!" => "0"
    "@" | "*" => self.env.get("@").unwrap_or("")
    "-" => {
      let buf = StringBuilder::new()
      if self.options.errexit { buf.write_char('e') }
      if self.options.nounset { buf.write_char('u') }
      if self.options.xtrace { buf.write_char('x') }
      buf.to_string()
    }
    _ => self.expand_named_variable(name)
  }
}

fn ExecContext::expand_named_variable(self : ExecContext, name : String) -> String {
  match parse_array_reference_name(name) {
    Some((base, index_expr)) => self.expand_array_element_reference(base, index_expr)
    None => {
      match self.env.get("__MOON_BASH_NAMEREF__" + name) {
        Some(target) => self.env.get(target).unwrap_or("")
        None => self.env.get(name).unwrap_or("")
      }
    }
  }
}

fn ExecContext::expand_array_element_reference(
  self : ExecContext,
  base : String,
  index_expr : String
) -> String {
  if index_expr == "@" || index_expr == "*" {
    return self.env.get("\{base}[\{index_expr}]").unwrap_or("")
  }

  let trimmed = trim_ascii_space_simple(index_expr)
  let literal_key = strip_wrapping_quotes(trimmed)
  let literal_lookup = "\{base}[\{literal_key}]"
  if self.env.contains(literal_lookup) {
    return self.env.get(literal_lookup).unwrap_or("")
  }

  match self.env.get(literal_key) {
    Some(indirect_key) => {
      let lookup = "\{base}[\{indirect_key}]"
      if self.env.contains(lookup) {
        return self.env.get(lookup).unwrap_or("")
      }
    }
    None => ()
  }

  let expanded_index = self.expand_word_to_string(@parser.parse_word_content(trimmed))
  if expanded_index.length() > 0 {
    let expanded_lookup = "\{base}[\{expanded_index}]"
    if self.env.contains(expanded_lookup) {
      return self.env.get(expanded_lookup).unwrap_or("")
    }
  }

  let numeric_index = self.eval_arith(@ast.ArithExpr::Raw(trimmed))
  let resolved_numeric_index = if numeric_index < 0 {
    let count_key = "__MOON_BASH_ARRAY_COUNT__" + base
    let count = parse_int_str(self.env.get(count_key).unwrap_or("0"))
    count + numeric_index
  } else {
    numeric_index
  }
  if resolved_numeric_index < 0 {
    return ""
  }
  let numeric_lookup = "\{base}[\{resolved_numeric_index.to_string()}]"
  if self.env.contains(numeric_lookup) {
    return self.env.get(numeric_lookup).unwrap_or("")
  }

  ""
}

// ============================================================================
// Parameter Expansion
// ============================================================================

fn ExecContext::expand_param(
  self : ExecContext,
  pe : @ast.ParamExpansion
) -> String {
  match pe {
    @ast.ParamExpansion::Simple(name) => self.expand_variable(name)
    @ast.ParamExpansion::Default(name, word, colon) => {
      let value = self.expand_variable(name)
      if colon {
        if value.length() == 0 {
          self.expand_word_to_string(word)
        } else {
          value
        }
      } else {
        if not(self.env.contains(name)) {
          self.expand_word_to_string(word)
        } else {
          value
        }
      }
    }
    @ast.ParamExpansion::Assign(name, word, colon) => {
      let value = self.expand_variable(name)
      if colon {
        if value.length() == 0 {
          let new_val = self.expand_word_to_string(word)
          self.env[name] = new_val
          new_val
        } else {
          value
        }
      } else {
        if not(self.env.contains(name)) {
          let new_val = self.expand_word_to_string(word)
          self.env[name] = new_val
          new_val
        } else {
          value
        }
      }
    }
    @ast.ParamExpansion::Error(name, msg_word, colon) => {
      let value = self.expand_variable(name)
      let is_error = if colon {
        value.length() == 0
      } else {
        not(self.env.contains(name))
      }
      if is_error {
        let msg = match msg_word {
          Some(w) => self.expand_word_to_string(w)
          None => "parameter null or not set"
        }
        self.stderr_buf.write_string("moon_bash: \{name}: \{msg}\n")
        self.exit_code = 1
        ""
      } else {
        value
      }
    }
    @ast.ParamExpansion::Alternative(name, word, colon) => {
      let value = self.expand_variable(name)
      if colon {
        if value.length() > 0 {
          self.expand_word_to_string(word)
        } else {
          ""
        }
      } else {
        if self.env.contains(name) {
          self.expand_word_to_string(word)
        } else {
          ""
        }
      }
    }
    @ast.ParamExpansion::Length(name) => {
      match array_count_var_name(name) {
        Some(count_key) => self.env.get(count_key).unwrap_or("0")
        None => {
          let value = self.expand_variable(name)
          value.length().to_string()
        }
      }
    }
    @ast.ParamExpansion::PrefixRemove(name, pattern, greedy) => {
      let value = self.expand_variable(name)
      let pat = self.expand_word_to_string(pattern)
      strip_prefix_pattern(value, pat, greedy)
    }
    @ast.ParamExpansion::SuffixRemove(name, pattern, greedy) => {
      let value = self.expand_variable(name)
      let pat = self.expand_word_to_string(pattern)
      strip_suffix_pattern(value, pat, greedy)
    }
    @ast.ParamExpansion::Replace(name, pattern, replacement, mode) => {
      let value = self.expand_variable(name)
      let pat = self.expand_word_to_string(pattern)
      let repl = match replacement {
        Some(w) => self.expand_word_to_string(w)
        None => ""
      }
      replace_pattern(value, pat, repl, mode)
    }
    @ast.ParamExpansion::Uppercase(name, _pattern, all) => {
      let value = self.expand_variable(name)
      if all { to_upper(value) } else { upper_first(value) }
    }
    @ast.ParamExpansion::Lowercase(name, _pattern, all) => {
      let value = self.expand_variable(name)
      if all { to_lower(value) } else { lower_first(value) }
    }
    @ast.ParamExpansion::Substring(name, offset_expr, length_expr) => {
      let offset = self.eval_arith(offset_expr)
      let len = match length_expr {
        Some(le) => Some(self.eval_arith(le))
        None => None
      }
      match parse_array_reference_name(name) {
        Some((base, index_expr)) if index_expr == "@" || index_expr == "*" => {
          let values = self.expand_array_elements_for_words(base)
          let sliced = slice_array_values(values, offset, len)
          sliced.iter().fold(
            init="",
            fn(acc, value) { if acc.length() == 0 { value } else { acc + " " + value } },
          )
        }
        _ => {
          let value = self.expand_variable(name)
          expand_scalar_substring(value, offset, len)
        }
      }
    }
    @ast.ParamExpansion::Indirection(name) => {
      match indirection_array_keys_name(name) {
        Some(base) => self.expand_array_keys(base)
        None => {
          match indirection_prefix_name(name) {
            Some(prefix) => self.expand_variables_with_prefix(prefix)
            None => {
              let indirect_name = self.expand_variable(name)
              self.expand_variable(indirect_name)
            }
          }
        }
      }
    }
  }
}

fn expand_scalar_substring(value : String, offset : Int64, len : Int64?) -> String {
  let value_len = value.length().to_int64()
  let actual_offset = if offset < 0L {
    let o = value_len + offset
    if o < 0L { 0L } else { o }
  } else {
    offset
  }
  let actual_len = match len {
    Some(length) => length
    None => value_len
  }
  let end = if actual_offset + actual_len > value_len {
    value_len
  } else {
    actual_offset + actual_len
  }
  if actual_offset >= value_len || actual_len <= 0L {
    ""
  } else {
    value.view(start_offset=actual_offset.to_int(), end_offset=end.to_int()).to_string()
  }
}

fn slice_array_values(values : Array[String], offset : Int64, len : Int64?) -> Array[String] {
  let out : Array[String] = []
  let values_len = values.length().to_int64()
  let mut start = if offset < 0L {
    values_len + offset
  } else {
    offset
  }
  if start < 0L {
    start = 0L
  }
  if start >= values_len {
    return out
  }
  let mut end_ = values_len
  match len {
    Some(length) => {
      if length <= 0L {
        return out
      }
      end_ = start + length
      if end_ > values_len {
        end_ = values_len
      }
    }
    None => ()
  }
  for i = start.to_int(); i < end_.to_int(); i = i + 1 {
    out.push(values[i])
  }
  out
}

// ============================================================================
// Command Substitution
// ============================================================================

fn clone_string_map(source : Map[String, String]) -> Map[String, String] {
  let copied : Map[String, String] = {}
  for key, value in source {
    copied[key] = value
  }
  copied
}

fn clone_bool_map(source : Map[String, Bool]) -> Map[String, Bool] {
  let copied : Map[String, Bool] = {}
  for key, value in source {
    copied[key] = value
  }
  copied
}

fn clone_function_map(
  source : Map[String, @ast.FunctionDef]
) -> Map[String, @ast.FunctionDef] {
  let copied : Map[String, @ast.FunctionDef] = {}
  for key, value in source {
    copied[key] = value
  }
  copied
}

fn ExecContext::expand_command_sub(
  self : ExecContext,
  script_str : String
) -> String {
  if self.substitution_depth >= self.limits.max_substitution_depth {
    self.fail_execution_limit("Command substitution nesting limit exceeded")
    return ""
  }
  self.substitution_depth += 1

  // Save current I/O state
  let saved_stdout = self.stdout_buf
  let saved_stdin = self.stdin_buf
  let saved_env = clone_string_map(self.env)
  let saved_exported = clone_bool_map(self.exported)
  let saved_functions = clone_function_map(self.functions)

  // Execute in a sub-context
  self.stdout_buf = StringBuilder::new()
  self.env = clone_string_map(saved_env)
  self.exported = clone_bool_map(saved_exported)
  self.functions = clone_function_map(saved_functions)

  let parsed = try {
    @parser.parse(script_str)
  } catch {
    @ast.BashError(_msg) => {
      self.substitution_depth -= 1
      self.stdout_buf = saved_stdout
      self.stdin_buf = saved_stdin
      self.env = saved_env
      self.exported = saved_exported
      self.functions = saved_functions
      return ""
    }
  }
  self.execute_script(parsed)

  let output = self.stdout_buf.to_string()

  // Restore I/O
  self.stdout_buf = saved_stdout
  self.stdin_buf = saved_stdin
  self.env = saved_env
  self.exported = saved_exported
  self.functions = saved_functions
  self.substitution_depth -= 1

  // Strip trailing newlines (bash behavior)
  let stripped = strip_trailing_newlines(output)
  if stripped.length() > self.limits.max_string_length {
    self.fail_execution_limit("string length limit exceeded")
    return ""
  }
  stripped
}

// ============================================================================
// Tilde Expansion
// ============================================================================

fn ExecContext::expand_tilde(self : ExecContext, user : String) -> String {
  if user.length() == 0 {
    self.env.get("HOME").unwrap_or("/home/user")
  } else {
    "/home/" + user
  }
}

// ============================================================================
// Arithmetic Evaluation
// ============================================================================

priv enum ArithTarget {
  NoTarget
  Var(String)
  ArrayElem(String, Int64)
}

