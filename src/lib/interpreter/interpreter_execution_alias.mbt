// moon_bash Interpreter - Alias Processing and Assignment Helpers

let alias_runtime_disable_key : String = "__MOON_BASH_ALIAS_EXPANSION_DISABLED"

fn alias_expansion_candidate_name(word : @ast.Word) -> String? {
  if word.parts.length() == 0 {
    return None
  }
  let value = StringBuilder::new()
  for part in word.parts {
    match part {
      @ast.WordPart::Literal(text) => value.write_string(text)
      _ => return None
    }
  }
  let name = value.to_string()
  if name.length() == 0 {
    None
  } else {
    Some(name)
  }
}

fn alias_is_blank_char(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn alias_is_operator_char(ch : Char) -> Bool {
  ch == ';' ||
  ch == '|' ||
  ch == '&' ||
  ch == '(' ||
  ch == ')' ||
  ch == '<' ||
  ch == '>' ||
  ch == '{' ||
  ch == '}'
}

fn alias_first_word_span(source : String) -> (Int, Int, String)? {
  let mut i = 0
  while i < source.length() {
    let ch = source[i].to_int().unsafe_to_char()
    if not(alias_is_blank_char(ch)) {
      break
    }
    i += 1
  }
  if i >= source.length() {
    return None
  }
  let first = source[i].to_int().unsafe_to_char()
  if alias_is_operator_char(first) || first == '\'' || first == '"' {
    return None
  }

  let start = i
  while i < source.length() {
    let ch = source[i].to_int().unsafe_to_char()
    if alias_is_blank_char(ch) || alias_is_operator_char(ch) {
      break
    }
    if ch == '\'' || ch == '"' || ch == '\\' {
      return None
    }
    i += 1
  }
  if i <= start {
    return None
  }

  let word = substring_slice(source, start, i)
  if word.length() == 0 {
    None
  } else {
    Some((start, i, word))
  }
}

fn append_alias_call_args(source : String, args : Array[String]) -> String {
  if args.length() == 0 {
    return source
  }

  let out = StringBuilder::new()
  out.write_string(source)
  if source.length() > 0 {
    let last = source[source.length() - 1].to_int().unsafe_to_char()
    if not(alias_is_blank_char(last)) {
      out.write_char(' ')
    }
  }
  for i = 0; i < args.length(); i = i + 1 {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(printf_shell_quote(args[i]))
  }
  out.to_string()
}

fn ExecContext::resolve_alias_command_source(
  self : ExecContext,
  alias_name : String,
  args : Array[String]
) -> String? {
  let mut source = match self.lookup_alias_value(alias_name) {
    Some(value) => value
    None => return None
  }

  let seen : Map[String, Bool] = {}
  seen[alias_name] = true

  let mut steps = 0
  while steps < 64 {
    steps += 1
    match alias_first_word_span(source) {
      Some((start, end_, first_word)) => {
        if seen.contains(first_word) {
          break
        }
        match self.lookup_alias_value(first_word) {
          Some(next_value) => {
            seen[first_word] = true
            source =
              substring_slice(source, 0, start) +
              next_value +
              substring_slice(source, end_, source.length())
          }
          None => break
        }
      }
      None => break
    }
  }

  Some(append_alias_call_args(source, args))
}

fn ExecContext::try_execute_alias_command(
  self : ExecContext,
  alias_candidate : String?,
  args : Array[String],
  has_multiline_literal_arg : Bool
) -> Bool {
  if not(self.shopt_is_enabled("expand_aliases")) {
    return false
  }
  if self.env.get(alias_runtime_disable_key).unwrap_or("") == "1" {
    return false
  }

  let alias_name = match alias_candidate {
    Some(name) => name
    None => return false
  }

  let source = match self.resolve_alias_command_source(alias_name, args) {
    Some(text) => text
    None => return false
  }

  if has_multiline_literal_arg {
    self.exit_code = 2
    return true
  }

  let parsed = try {
    @parser.parse(source)
  } catch {
    @ast.BashError(_msg) => {
      self.exit_code = 2
      return true
    }
  }

  let saved_disable = self.env.get(alias_runtime_disable_key)
  self.env[alias_runtime_disable_key] = "1"
  self.execute_script(parsed)
  match saved_disable {
    Some(value) => self.env[alias_runtime_disable_key] = value
    None => self.env.remove(alias_runtime_disable_key)
  }
  true
}

fn alias_call_has_multiline_literal_arg(words : Array[@ast.Word]) -> Bool {
  if words.length() <= 1 {
    return false
  }
  for i = 1; i < words.length(); i = i + 1 {
    if word_has_literal_newline(words[i]) {
      return true
    }
  }
  false
}

fn word_has_literal_newline(word : @ast.Word) -> Bool {
  for part in word.parts {
    if word_part_has_literal_newline(part) {
      return true
    }
  }
  false
}

fn word_part_has_literal_newline(part : @ast.WordPart) -> Bool {
  match part {
    @ast.WordPart::Literal(text) => contains_char(text, '\n')
    @ast.WordPart::SingleQuoted(text) => contains_char(text, '\n')
    @ast.WordPart::DoubleQuoted(inner) => {
      for nested in inner {
        if word_part_has_literal_newline(nested) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

fn contains_char(text : String, target : Char) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int().unsafe_to_char() == target {
      return true
    }
  }
  false
}

fn ExecContext::resolve_array_assignment_target(
  self : ExecContext,
  raw_name : String
) -> (String, String)? {
  match parse_array_element_assignment_name(raw_name) {
    Some((base, index_expr)) => {
      let trimmed = trim_ascii_space_simple(index_expr)
      if trimmed.length() == 0 {
        return Some((base, index_expr))
      }

      let expanded_index = self.expand_array_index_expr(trimmed)
      if self.should_exit {
        return Some((base, index_expr))
      }
      let mut resolved_index = if expanded_index.length() > 0 { expanded_index } else { trimmed }
      if arith_is_identifier_text(trimmed) {
        let dynamic_raw = self.env.get(trimmed).unwrap_or("")
        if dynamic_raw.length() > 0 {
          let dynamic_expanded = self.expand_array_index_expr(dynamic_raw)
          if self.should_exit {
            return Some((base, index_expr))
          }
          resolved_index = if dynamic_expanded.length() > 0 { dynamic_expanded } else { dynamic_raw }
        }
      }
      if contains_char(resolved_index, '$') {
        let second_pass = self.expand_array_index_expr(resolved_index)
        if self.should_exit {
          return Some((base, index_expr))
        }
        if second_pass.length() > 0 {
          resolved_index = second_pass
        }
      }

      let array_kind_key = "__MOON_BASH_ARRAY_KIND__" + base
      if self.env.get(array_kind_key).unwrap_or("") == "assoc" {
        return Some((base, resolved_index))
      }

      if contains_char(resolved_index, '#') {
        self.exit_code = 1
        self.should_exit = true
        return Some((base, resolved_index))
      }

      let raw_index = self.eval_arith(@ast.ArithExpr::Raw(resolved_index))
      let count_key = "__MOON_BASH_ARRAY_COUNT__" + base
      let count = parse_int32_str(self.env.get(count_key).unwrap_or("0")).to_int64()
      let final_index = if raw_index < 0L { count + raw_index } else { raw_index }
      if final_index < 0L {
        return Some((base, raw_index.to_string()))
      }
      Some((base, final_index.to_string()))
    }
    None => None
  }
}

fn word_has_status_sensitive_expansion(word : @ast.Word) -> Bool {
  for part in word.parts {
    if word_part_has_status_sensitive_expansion(part) {
      return true
    }
  }
  false
}

fn word_part_has_status_sensitive_expansion(part : @ast.WordPart) -> Bool {
  match part {
    @ast.WordPart::CommandSubstitution(_) => true
    @ast.WordPart::ArithmeticExpansion(_) => true
    @ast.WordPart::DoubleQuoted(inner) => {
      for nested in inner {
        if word_part_has_status_sensitive_expansion(nested) {
          return true
        }
      }
      false
    }
    @ast.WordPart::BraceExpansion(options) => {
      for option in options {
        for nested in option {
          if word_part_has_status_sensitive_expansion(nested) {
            return true
          }
        }
      }
      false
    }
    @ast.WordPart::ParameterExpansion(expansion) =>
      param_expansion_has_status_sensitive_expansion(expansion)
    _ => false
  }
}

fn param_expansion_has_status_sensitive_expansion(
  expansion : @ast.ParamExpansion
) -> Bool {
  match expansion {
    @ast.ParamExpansion::Default(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::Assign(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::Error(_, maybe_word, _) =>
      match maybe_word {
        Some(word) => word_has_status_sensitive_expansion(word)
        None => false
      }
    @ast.ParamExpansion::Alternative(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::PrefixRemove(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::SuffixRemove(_, word, _) => word_has_status_sensitive_expansion(word)
    @ast.ParamExpansion::Replace(_, pattern, maybe_repl, _) => {
      if word_has_status_sensitive_expansion(pattern) {
        return true
      }
      match maybe_repl {
        Some(repl) => word_has_status_sensitive_expansion(repl)
        None => false
      }
    }
    @ast.ParamExpansion::Uppercase(_, maybe_pattern, _) =>
      match maybe_pattern {
        Some(pattern) => word_has_status_sensitive_expansion(pattern)
        None => false
      }
    @ast.ParamExpansion::Lowercase(_, maybe_pattern, _) =>
      match maybe_pattern {
        Some(pattern) => word_has_status_sensitive_expansion(pattern)
        None => false
      }
    _ => false
  }
}

fn is_grep_like_command(cmd_name : String) -> Bool {
  cmd_name == "grep" ||
  cmd_name == "egrep" ||
  cmd_name == "fgrep" ||
  cmd_name == "rg"
}

fn ExecContext::store_scalar_assignment(
  self : ExecContext,
  name : String,
  value : String
) -> Bool {
  self.store_scalar_assignment_with_options(name, value, true)
}

fn ExecContext::store_scalar_assignment_with_options(
  self : ExecContext,
  name : String,
  value : String,
  enforce_readonly : Bool
) -> Bool {
  if enforce_readonly && self.is_readonly_variable(name) {
    self.stderr_buf.write_string("moon_bash: \{name}: readonly variable\n")
    self.exit_code = 1
    return false
  }
  let final_value = self.apply_variable_attributes(name, value)
  if final_value.length() > self.limits.max_string_length {
    self.fail_execution_limit("string length limit exceeded")
    return false
  }
  self.env[name] = final_value
  true
}
