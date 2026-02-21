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
  if inner_parts.length() == 1 {
    match self.double_quoted_multiword_values(inner_parts[0]) {
      Some(values) => return Some(values)
      None => return None
    }
  }

  let mut multiword_index = -1
  let mut multiword_values : Array[String]? = None
  for i = 0; i < inner_parts.length(); i = i + 1 {
    match self.double_quoted_multiword_values(inner_parts[i]) {
      Some(values) => {
        if multiword_index >= 0 {
          return None
        }
        multiword_index = i
        multiword_values = Some(values)
      }
      None => ()
    }
  }
  if multiword_index < 0 {
    return None
  }

  let prefix_buf = StringBuilder::new()
  for i = 0; i < multiword_index; i = i + 1 {
    prefix_buf.write_string(self.expand_word_part(inner_parts[i]))
  }
  let suffix_buf = StringBuilder::new()
  for i = multiword_index + 1; i < inner_parts.length(); i = i + 1 {
    suffix_buf.write_string(self.expand_word_part(inner_parts[i]))
  }
  let prefix = prefix_buf.to_string()
  let suffix = suffix_buf.to_string()

  let values = multiword_values.unwrap_or([])
  if values.length() == 0 {
    return Some([])
  }
  if values.length() == 1 {
    return Some([prefix + values[0] + suffix])
  }
  let out : Array[String] = []
  out.push(prefix + values[0])
  for i = 1; i < values.length() - 1; i = i + 1 {
    out.push(values[i])
  }
  out.push(values[values.length() - 1] + suffix)
  Some(out)
}

fn ExecContext::double_quoted_multiword_values(
  self : ExecContext,
  part : @ast.WordPart
) -> Array[String]? {
  if is_positional_at_expansion(part) {
    return Some(self.expand_positional_parameters_for_words())
  }

  match part {
    @ast.WordPart::ParameterExpansion(pe) => {
      match self.expand_array_parameter_words(pe) {
        Some(values) => return Some(values)
        None => ()
      }
    }
    _ => ()
  }

  let (base, expand_keys) = match array_reference_base_for_at(part) {
    Some(pair) => pair
    None => return None
  }
  if expand_keys {
    Some(self.collect_array_keys(base))
  } else {
    Some(self.expand_array_elements_for_words(base))
  }
}

fn ExecContext::expand_array_parameter_words(
  self : ExecContext,
  pe : @ast.ParamExpansion
) -> Array[String]? {
  match pe {
    @ast.ParamExpansion::Simple(name) => {
      let (base_name, transform) = match parse_parameter_transform_name(name) {
        Some((raw, kind)) => (raw, Some(kind))
        None => (name, None)
      }
      match parse_array_reference_name(base_name) {
        Some((base, index)) => {
          if index == "@" {
            let values = self.expand_array_elements_for_words(base)
            Some(self.transform_array_values(base, values, transform))
          } else if index == "*" {
            let values = self.expand_array_elements_for_words(base)
            let transformed = self.transform_array_values(base, values, transform)
            Some([join_values_with_ifs(transformed, self.env.get("IFS").unwrap_or(" \t\n"))])
          } else {
            None
          }
        }
        None => None
      }
    }
    @ast.ParamExpansion::Indirection(name) => {
      match parse_indirection_array_keys_mode(name) {
        Some((base, join_with_ifs)) => {
          let keys = self.collect_array_keys(base)
          if join_with_ifs {
            Some([join_values_with_ifs(keys, self.env.get("IFS").unwrap_or(" \t\n"))])
          } else {
            Some(keys)
          }
        }
        None => None
      }
    }
    @ast.ParamExpansion::PrefixRemove(name, pattern, greedy) => {
      self.expand_array_parameter_transform(name, fn(value) {
        let pat = self.expand_word_to_string(pattern)
        strip_prefix_pattern(value, pat, greedy)
      })
    }
    @ast.ParamExpansion::SuffixRemove(name, pattern, greedy) => {
      self.expand_array_parameter_transform(name, fn(value) {
        let pat = self.expand_word_to_string(pattern)
        strip_suffix_pattern(value, pat, greedy)
      })
    }
    @ast.ParamExpansion::Replace(name, pattern, replacement, mode) => {
      self.expand_array_parameter_transform(name, fn(value) {
        let pat = self.expand_word_to_string(pattern)
        let repl = match replacement {
          Some(w) => self.expand_word_to_string(w)
          None => ""
        }
        replace_pattern(value, pat, repl, mode)
      })
    }
    @ast.ParamExpansion::Substring(name, offset_expr, length_expr) => {
      let offset = self.eval_arith(offset_expr)
      let len = match length_expr {
        Some(le) => Some(self.eval_arith(le))
        None => None
      }
      if name == "@" {
        return Some(self.slice_positional_parameters_for_substring(offset, len))
      }
      if name == "*" {
        let values = self.slice_positional_parameters_for_substring(offset, len)
        return Some([join_values_with_ifs(values, self.env.get("IFS").unwrap_or(" \t\n"))])
      }
      match parse_array_reference_name(name) {
        Some((base, index_expr)) if index_expr == "@" || index_expr == "*" => {
          if self.env.get(test_array_kind_storage_key(base)).unwrap_or("") == "assoc" {
            self.exit_code = 1
            self.should_exit = true
            Some([])
          } else {
            let sliced = self.expand_indexed_array_substring_values(base, offset, len)
            if index_expr == "*" {
              Some([join_values_with_ifs(sliced, self.env.get("IFS").unwrap_or(" \t\n"))])
            } else {
              Some(sliced)
            }
          }
        }
        _ => None
      }
    }
    _ => None
  }
}

fn ExecContext::expand_array_parameter_transform(
  self : ExecContext,
  name : String,
  transform : (String) -> String
) -> Array[String]? {
  match parse_array_reference_name(name) {
    Some((base, index)) => {
      let values = self.expand_array_elements_for_words(base)
      let transformed : Array[String] = []
      for value in values {
        transformed.push(transform(value))
      }
      if index == "*" {
        Some([join_values_with_ifs(transformed, self.env.get("IFS").unwrap_or(" \t\n"))])
      } else if index == "@" {
        Some(transformed)
      } else {
        None
      }
    }
    None => None
  }
}

fn parse_indirection_array_keys_mode(name : String) -> (String, Bool)? {
  if name.length() >= 3 {
    let suffix = name.view(start_offset=name.length() - 3, end_offset=name.length()).to_string()
    let base = name.view(start_offset=0, end_offset=name.length() - 3).to_string()
    if base.length() == 0 {
      return None
    }
    if suffix == "[@]" {
      return Some((base, false))
    }
    if suffix == "[*]" {
      return Some((base, true))
    }
  }
  None
}

fn join_values_with_ifs(values : Array[String], ifs : String) -> String {
  let sep = if ifs.length() == 0 {
    ""
  } else {
    ifs.view(start_offset=0, end_offset=1).to_string()
  }
  let out = StringBuilder::new()
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      out.write_string(sep)
    }
    out.write_string(values[i])
  }
  out.to_string()
}

fn parse_parameter_transform_name(name : String) -> (String, Char)? {
  if name.length() < 2 {
    return None
  }
  let marker = name[name.length() - 2].to_int().unsafe_to_char()
  if marker != '@' {
    return None
  }
  let transform = name[name.length() - 1].to_int().unsafe_to_char()
  if transform != 'Q' && transform != 'P' && transform != 'a' {
    return None
  }
  Some((
    name.view(start_offset=0, end_offset=name.length() - 2).to_string(),
    transform,
  ))
}

fn ExecContext::array_attribute_flag(self : ExecContext, base : String) -> String {
  if self.env.get(test_array_kind_storage_key(base)).unwrap_or("") == "assoc" {
    "A"
  } else {
    "a"
  }
}

fn ExecContext::transform_array_values(
  self : ExecContext,
  base : String,
  values : Array[String],
  transform : Char?
) -> Array[String] {
  match transform {
    Some('Q') => quote_array_values_for_q_transform(values)
    Some('a') => {
      let attrs : Array[String] = []
      let attr = self.array_attribute_flag(base)
      for _value in values {
        attrs.push(attr)
      }
      attrs
    }
    _ => values
  }
}

fn quote_array_values_for_q_transform(values : Array[String]) -> Array[String] {
  let quoted : Array[String] = []
  for value in values {
    quoted.push(quote_value_for_q_transform(value))
  }
  quoted
}

fn quote_value_for_q_transform(value : String) -> String {
  if value.length() == 0 {
    return "''"
  }

  let mut has_single_quote = false
  for i = 0; i < value.length(); i = i + 1 {
    if value[i].to_int().unsafe_to_char() == '\'' {
      has_single_quote = true
      break
    }
  }

  if not(has_single_quote) {
    return printf_shell_quote(value)
  }

  let out = StringBuilder::new()
  out.write_string("$'")
  for i = 0; i < value.length(); i = i + 1 {
    let ch = value[i].to_int().unsafe_to_char()
    match ch {
      '\\' => out.write_string("\\\\")
      '\'' => out.write_string("\\'")
      '\n' => out.write_string("\\n")
      '\t' => out.write_string("\\t")
      '\r' => out.write_string("\\r")
      _ => out.write_char(ch)
    }
  }
  out.write_char('\'')
  out.to_string()
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
        Some(target) => {
          if target == name {
            self.env.get(target).unwrap_or("")
          } else {
            self.expand_named_variable(target)
          }
        }
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
  if trimmed.length() == 0 {
    self.emit_bad_array_subscript(base, "\{base}[]")
    self.exit_code = 1
    self.env["__MOON_BASH_ABORT_CURRENT_COMMAND__"] = "1"
    return ""
  }
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

  let expanded_index = self.expand_array_index_expr(trimmed)
  if expanded_index.length() > 0 {
    let expanded_lookup = "\{base}[\{expanded_index}]"
    if self.env.contains(expanded_lookup) {
      return self.env.get(expanded_lookup).unwrap_or("")
    }
  }

  let mut resolved_index_expr = trimmed
  if arith_is_identifier_text(trimmed) {
    let dynamic_raw = self.env.get(trimmed).unwrap_or("")
    if dynamic_raw.length() > 0 {
      let dynamic_expanded = self.expand_array_index_expr(dynamic_raw)
      resolved_index_expr = if dynamic_expanded.length() > 0 { dynamic_expanded } else { dynamic_raw }
    }
  }
  if contains_char(resolved_index_expr, '$') {
    let second_pass = self.expand_array_index_expr(resolved_index_expr)
    if second_pass.length() > 0 {
      resolved_index_expr = second_pass
    }
  }

  let resolved_lookup = "\{base}[\{resolved_index_expr}]"
  if self.env.contains(resolved_lookup) {
    return self.env.get(resolved_lookup).unwrap_or("")
  }

  let numeric_index = self.eval_arith(@ast.ArithExpr::Raw(resolved_index_expr))
  let resolved_numeric_index = if numeric_index < 0 {
    self.indexed_array_origin(base) + numeric_index
  } else {
    numeric_index
  }
  if resolved_numeric_index < 0 {
    let fragment = "\{base}[\{resolved_index_expr}]"
    self.emit_bad_array_subscript(base, fragment)
    return ""
  }
  let numeric_lookup = "\{base}[\{resolved_numeric_index.to_string()}]"
  if self.env.contains(numeric_lookup) {
    return self.env.get(numeric_lookup).unwrap_or("")
  }

  ""
}

fn ExecContext::expand_array_index_expr(self : ExecContext, expr : String) -> String {
  let trimmed = trim_ascii_space_simple(expr)
  if trimmed.length() >= 2 {
    let first = trimmed[0].to_int().unsafe_to_char()
    let last = trimmed[trimmed.length() - 1].to_int().unsafe_to_char()
    if first == '\'' && last == '\'' {
      return trimmed.view(start_offset=1, end_offset=trimmed.length() - 1).to_string()
    }
    if first == '"' && last == '"' {
      let inner = trimmed.view(start_offset=1, end_offset=trimmed.length() - 1).to_string()
      return self.expand_word_to_string(@parser.parse_word_content(inner))
    }
  }
  self.expand_word_to_string(@parser.parse_word_content(trimmed))
}

// ============================================================================
// Parameter Expansion
// ============================================================================

fn ExecContext::expand_param(
  self : ExecContext,
  pe : @ast.ParamExpansion
) -> String {
  match pe {
    @ast.ParamExpansion::Simple(name) => self.expand_simple_parameter(name)
    @ast.ParamExpansion::Default(name, word, colon) => {
      let value = self.expand_variable(name)
      let is_set = self.parameter_is_set(name)
      let is_null = self.parameter_is_null(name, value)
      if colon {
        if is_null {
          self.expand_word_to_string(word)
        } else {
          value
        }
      } else {
        if not(is_set) {
          self.expand_word_to_string(word)
        } else {
          value
        }
      }
    }
    @ast.ParamExpansion::Assign(name, word, colon) => {
      let value = self.expand_variable(name)
      let is_set = self.parameter_is_set(name)
      let is_null = self.parameter_is_null(name, value)
      if colon {
        if is_null {
          let new_val = self.expand_word_to_string(word)
          self.env[name] = new_val
          new_val
        } else {
          value
        }
      } else {
        if not(is_set) {
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
      let is_set = self.parameter_is_set(name)
      let is_null = self.parameter_is_null(name, value)
      let is_error = if colon {
        is_null
      } else {
        not(is_set)
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
      let is_set = self.parameter_is_set(name)
      let is_null = self.parameter_is_null(name, value)
      if colon {
        if not(is_null) {
          self.expand_word_to_string(word)
        } else {
          ""
        }
      } else {
        if is_set {
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
      if name == "*" || name == "@" {
        let values = self.slice_positional_parameters_for_substring(offset, len)
        return join_values_with_space(values)
      }
      match parse_array_reference_name(name) {
        Some((base, index_expr)) if index_expr == "@" || index_expr == "*" => {
          if self.env.get(test_array_kind_storage_key(base)).unwrap_or("") == "assoc" {
            self.exit_code = 1
            self.should_exit = true
            ""
          } else {
            let sliced = self.expand_indexed_array_substring_values(base, offset, len)
            if index_expr == "*" {
              join_values_with_ifs(sliced, self.env.get("IFS").unwrap_or(" \t\n"))
            } else {
              join_values_with_space(sliced)
            }
          }
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

fn ExecContext::parameter_is_set(self : ExecContext, name : String) -> Bool {
  match parse_array_reference_name(name) {
    Some((base, index)) => {
      if index == "@" || index == "*" {
        let count = parse_int32_str(self.env.get(test_array_count_storage_key(base)).unwrap_or("-1"))
        if count >= 0 {
          return count > 0
        }
        return self.env.contains(base) || self.env.contains("\{base}[\{index}]")
      }
      self.env.contains("\{base}[\{index}]")
    }
    None => {
      match self.env.get(test_array_count_storage_key(name)) {
        Some(raw_count) => parse_int32_str(raw_count) > 0
        None => self.env.contains(name)
      }
    }
  }
}

fn ExecContext::parameter_is_null(
  self : ExecContext,
  name : String,
  value : String
) -> Bool {
  match parse_array_reference_name(name) {
    Some((base, index)) => {
      if index == "@" || index == "*" {
        let count = parse_int32_str(self.env.get(test_array_count_storage_key(base)).unwrap_or("-1"))
        if count <= 0 {
          return true
        }
        if count == 1 {
          let values = self.expand_array_elements_for_words(base)
          return values.length() == 0 || values[0].length() == 0
        }
        return false
      }
      value.length() == 0
    }
    None => {
      match self.env.get(test_array_count_storage_key(name)) {
        Some(raw_count) => {
          let count = parse_int32_str(raw_count)
          if count <= 0 {
            true
          } else {
            value.length() == 0
          }
        }
        None => value.length() == 0
      }
    }
  }
}

fn ExecContext::expand_simple_parameter(
  self : ExecContext,
  name : String
) -> String {
  match parse_parameter_transform_name(name) {
    Some((base_name, transform)) => self.expand_parameter_transform(base_name, transform)
    None => self.expand_variable(name)
  }
}

fn ExecContext::expand_parameter_transform(
  self : ExecContext,
  base_name : String,
  transform : Char
) -> String {
  match parse_array_reference_name(base_name) {
    Some((base, index)) => {
      if index == "@" || index == "*" {
        let values = self.expand_array_elements_for_words(base)
        let transformed = self.transform_array_values(base, values, Some(transform))
        if index == "*" {
          join_values_with_ifs(transformed, self.env.get("IFS").unwrap_or(" \t\n"))
        } else {
          join_values_with_space(transformed)
        }
      } else {
        self.expand_variable(base_name)
      }
    }
    None => {
      let value = self.expand_variable(base_name)
      match transform {
        'Q' => quote_value_for_q_transform(value)
        'a' => {
          if self.env.contains(test_array_count_storage_key(base_name)) {
            self.array_attribute_flag(base_name)
          } else {
            ""
          }
        }
        _ => value
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

fn join_values_with_space(values : Array[String]) -> String {
  let out = StringBuilder::new()
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(values[i])
  }
  out.to_string()
}

fn ExecContext::slice_positional_parameters_for_substring(
  self : ExecContext,
  offset : Int64,
  len : Int64?
) -> Array[String] {
  let count = match self.env.get("#") {
    Some(raw) => parse_int32_str(raw)
    None => 0
  }
  let values : Array[String] = []
  let script_name = match self.env.get("0") {
    Some(v) => v
    None => {
      match self.env.get("SH") {
        Some(v) => v
        None => self.env.get("SHELL").unwrap_or("")
      }
    }
  }
  values.push(script_name)
  for i = 1; i <= count; i = i + 1 {
    values.push(self.env.get(i.to_string()).unwrap_or(""))
  }

  let values_len = values.length().to_int64()
  let origin = count.to_int64() + 1L
  let start = if offset < 0L {
    origin + offset
  } else {
    offset
  }
  if start < 0L || start >= values_len {
    return []
  }

  let mut end_ = values_len
  match len {
    Some(length) => {
      if length <= 0L {
        return []
      }
      end_ = start + length
      if end_ > values_len {
        end_ = values_len
      }
    }
    None => ()
  }

  let out : Array[String] = []
  for i = start.to_int(); i < end_.to_int(); i = i + 1 {
    out.push(values[i])
  }
  out
}

fn ExecContext::expand_indexed_array_substring_values(
  self : ExecContext,
  base : String,
  offset : Int64,
  len : Int64?
) -> Array[String] {
  let keys = self.collect_array_keys(base)
  if keys.length() == 0 {
    let values = self.expand_array_elements_for_words(base)
    return slice_array_values(values, offset, len)
  }

  let start = if offset < 0L {
    self.indexed_array_origin(base) + offset
  } else {
    offset
  }
  if start < 0L {
    return []
  }

  let out : Array[String] = []
  let mut remaining = match len {
    Some(length) => {
      if length <= 0L {
        return []
      }
      length
    }
    None => -1L
  }

  for key in keys {
    match parse_non_negative_int_for_sort(key) {
      Some(index) => {
        if index.to_int64() >= start {
          if remaining != 0L {
            out.push(self.env.get("\{base}[\{key}]").unwrap_or(""))
            if remaining > 0L {
              remaining -= 1L
            }
          }
        }
      }
      None => ()
    }
  }
  out
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
