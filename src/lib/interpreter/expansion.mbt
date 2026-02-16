// MoonBash Interpreter - Word Expansion
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
    None => self.env.get(name).unwrap_or("")
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

  let numeric_index = self.eval_arith(@ast.ArithExpr::Raw(trimmed))
  let numeric_lookup = "\{base}[\{numeric_index.to_string()}]"
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
        self.stderr_buf.write_string("moonbash: \{name}: \{msg}\n")
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
      let value = self.expand_variable(name)
      let offset = self.eval_arith(offset_expr)
      let len = match length_expr {
        Some(le) => self.eval_arith(le)
        None => value.length()
      }
      let actual_offset = if offset < 0 {
        let o = value.length() + offset
        if o < 0 { 0 } else { o }
      } else {
        offset
      }
      let end = if actual_offset + len > value.length() {
        value.length()
      } else {
        actual_offset + len
      }
      if actual_offset >= value.length() {
        ""
      } else {
        value.substring(start=actual_offset, end=end)
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

// ============================================================================
// Command Substitution
// ============================================================================

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
  let saved_env = self.env
  let saved_exported = self.exported
  let saved_functions = self.functions

  // Execute in a sub-context
  self.stdout_buf = StringBuilder::new()

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
  ArrayElem(String, Int)
}

priv struct ArithValue {
  value : Int
  target : ArithTarget
}

priv struct ArithParser {
  tokens : Array[String]
  mut pos : Int
}

fn arith_plain(value : Int) -> ArithValue {
  { value, target: NoTarget }
}

fn arith_with_target(value : Int, target : ArithTarget) -> ArithValue {
  { value, target }
}

fn ArithParser::peek(self : ArithParser) -> String? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

fn ArithParser::advance(self : ArithParser) -> String? {
  if self.pos < self.tokens.length() {
    let tok = self.tokens[self.pos]
    self.pos += 1
    Some(tok)
  } else {
    None
  }
}

fn ArithParser::match_tok(self : ArithParser, tok : String) -> Bool {
  match self.peek() {
    Some(cur) => {
      if cur == tok {
        self.pos += 1
        true
      } else {
        false
      }
    }
    None => false
  }
}

fn arith_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn arith_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn arith_is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

fn arith_is_ident_char(ch : Char) -> Bool {
  arith_is_ident_start(ch) || arith_is_digit(ch)
}

fn arith_is_hex_digit(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'a' && ch <= 'f') ||
  (ch >= 'A' && ch <= 'F')
}

fn arith_is_base_digit_char(ch : Char) -> Bool {
  arith_is_digit(ch) ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '@' ||
  ch == '_'
}

fn arith_trim(s : String) -> String {
  let mut start = 0
  let mut end_ = s.length()

  while start < end_ {
    let ch = s[start].to_int().unsafe_to_char()
    if arith_is_space(ch) {
      start += 1
    } else {
      break
    }
  }

  while end_ > start {
    let ch = s[end_ - 1].to_int().unsafe_to_char()
    if arith_is_space(ch) {
      end_ -= 1
    } else {
      break
    }
  }

  s.substring(start=start, end=end_)
}

fn arith_is_identifier_text(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let first = s[0].to_int().unsafe_to_char()
  if not(arith_is_ident_start(first)) {
    return false
  }
  for i = 1; i < s.length(); i = i + 1 {
    if not(arith_is_ident_char(s[i].to_int().unsafe_to_char())) {
      return false
    }
  }
  true
}

fn arith_parse_decimal_str(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut value = 0
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if not(arith_is_digit(ch)) {
      return None
    }
    value = value * 10 + (ch.to_int() - 48)
  }
  Some(value)
}

fn arith_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - 48)
  } else if ch >= 'a' && ch <= 'z' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'Z' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else if ch == '@' {
    Some(62)
  } else if ch == '_' {
    Some(63)
  } else {
    None
  }
}

fn arith_parse_base_digits(digits : String, base : Int) -> Int? {
  if digits.length() == 0 {
    return None
  }
  let mut value = 0
  for i = 0; i < digits.length(); i = i + 1 {
    let ch = digits[i].to_int().unsafe_to_char()
    match arith_digit_value(ch) {
      Some(d) => {
        if d >= base {
          return None
        }
        value = value * base + d
      }
      None => return None
    }
  }
  Some(value)
}

fn arith_parse_number_literal(token : String) -> Int? {
  if token.length() == 0 {
    return None
  }

  let mut start = 0
  let mut sign = 1
  if token[0] == '+' {
    start = 1
  } else if token[0] == '-' {
    sign = -1
    start = 1
  }
  if start >= token.length() {
    return None
  }

  let body = token.substring(start=start)

  if body.length() >= 3 &&
    body[0] == '0' &&
    (body[1] == 'x' || body[1] == 'X') {
    let digits = body.substring(start=2)
    match arith_parse_base_digits(digits, 16) {
      Some(v) => return Some(v * sign)
      None => return None
    }
  }

  let mut hash_pos = -1
  for i = 0; i < body.length(); i = i + 1 {
    if body[i] == '#' {
      hash_pos = i
      break
    }
  }
  if hash_pos > 0 {
    let base_text = body.substring(start=0, end=hash_pos)
    let digits = body.substring(start=hash_pos + 1)
    match arith_parse_decimal_str(base_text) {
      Some(base) => {
        if base < 2 || base > 64 {
          return None
        }
        match arith_parse_base_digits(digits, base) {
          Some(v) => return Some(v * sign)
          None => return None
        }
      }
      None => return None
    }
  }

  if body.length() > 1 && body[0] == '0' {
    let digits = body.substring(start=1)
    let mut is_octal = true
    for i = 0; i < digits.length(); i = i + 1 {
      let ch = digits[i].to_int().unsafe_to_char()
      if ch < '0' || ch > '7' {
        is_octal = false
        break
      }
    }
    if is_octal {
      match arith_parse_base_digits(digits, 8) {
        Some(v) => return Some(v * sign)
        None => return None
      }
    }
  }

  match arith_parse_decimal_str(body) {
    Some(v) => Some(v * sign)
    None => None
  }
}

fn arith_tokenize(expr : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut i = 0

  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()

    if arith_is_space(ch) {
      i += 1
      continue
    }

    if arith_is_ident_start(ch) {
      let start = i
      i += 1
      while i < expr.length() && arith_is_ident_char(expr[i].to_int().unsafe_to_char()) {
        i += 1
      }
      tokens.push(expr.substring(start=start, end=i))
      continue
    }

    if arith_is_digit(ch) {
      let start = i
      if i + 1 < expr.length() &&
        ch == '0' &&
        (expr[i + 1] == 'x' || expr[i + 1] == 'X') {
        i += 2
        while i < expr.length() && arith_is_hex_digit(expr[i].to_int().unsafe_to_char()) {
          i += 1
        }
        tokens.push(expr.substring(start=start, end=i))
        continue
      }

      while i < expr.length() && arith_is_digit(expr[i].to_int().unsafe_to_char()) {
        i += 1
      }

      if i < expr.length() && expr[i] == '#' {
        i += 1
        while i < expr.length() && arith_is_base_digit_char(expr[i].to_int().unsafe_to_char()) {
          i += 1
        }
        tokens.push(expr.substring(start=start, end=i))
        continue
      }

      while i < expr.length() && arith_is_ident_char(expr[i].to_int().unsafe_to_char()) {
        i += 1
      }
      tokens.push(expr.substring(start=start, end=i))
      continue
    }

    if i + 2 < expr.length() {
      let a = expr[i].to_int().unsafe_to_char()
      let b = expr[i + 1].to_int().unsafe_to_char()
      let c = expr[i + 2].to_int().unsafe_to_char()
      if a == '<' && b == '<' && c == '=' {
        tokens.push("<<=")
        i += 3
        continue
      }
      if a == '>' && b == '>' && c == '=' {
        tokens.push(">>=")
        i += 3
        continue
      }
    }

    if i + 1 < expr.length() {
      let a = expr[i].to_int().unsafe_to_char()
      let b = expr[i + 1].to_int().unsafe_to_char()
      if (a == '+' && b == '+') ||
        (a == '-' && b == '-') ||
        (a == '&' && b == '&') ||
        (a == '|' && b == '|') ||
        (a == '=' && b == '=') ||
        (a == '!' && b == '=') ||
        (a == '<' && b == '=') ||
        (a == '>' && b == '=') ||
        (a == '+' && b == '=') ||
        (a == '-' && b == '=') ||
        (a == '*' && b == '=') ||
        (a == '/' && b == '=') ||
        (a == '%' && b == '=') ||
        (a == '&' && b == '=') ||
        (a == '|' && b == '=') ||
        (a == '^' && b == '=') ||
        (a == '<' && b == '<') ||
        (a == '>' && b == '>') {
        tokens.push(expr.substring(start=i, end=i + 2))
        i += 2
        continue
      }
    }

    match ch {
      '+' | '-' | '*' | '/' | '%' | '=' | '!' | '~' | '<' | '>' | '&' | '|'
      | '^' | '?' | ':' | ',' | '(' | ')' | '[' | ']' => {
        tokens.push(expr.substring(start=i, end=i + 1))
        i += 1
      }
      _ => {
        // Ignore unsupported characters without failing the whole expression.
        i += 1
      }
    }
  }

  tokens
}

fn arith_is_assignment_op(op : String) -> Bool {
  op == "=" ||
  op == "+=" ||
  op == "-=" ||
  op == "*=" ||
  op == "/=" ||
  op == "%=" ||
  op == "&=" ||
  op == "|=" ||
  op == "^=" ||
  op == "<<=" ||
  op == ">>="
}

fn arith_shift_left(v : Int, amount : Int) -> Int {
  if amount < 0 {
    v
  } else {
    v << amount
  }
}

fn arith_shift_right(v : Int, amount : Int) -> Int {
  if amount < 0 {
    v
  } else {
    v >> amount
  }
}

fn ExecContext::arith_parse_value_text(self : ExecContext, text : String) -> Int {
  let trimmed = arith_trim(text)
  if trimmed.length() == 0 {
    return 0
  }

  if trimmed.length() >= 2 &&
    trimmed[0] == '(' &&
    trimmed[trimmed.length() - 1] == ')' {
    let inner = trimmed.substring(start=1, end=trimmed.length() - 1)
    let parts = split_by_whitespace(inner)
    if parts.length() == 0 {
      return 0
    }
    return self.arith_parse_value_text(parts[0])
  }

  match arith_parse_number_literal(trimmed) {
    Some(v) => v
    None => parse_int_str(trimmed)
  }
}

fn ExecContext::arith_get_var_value(self : ExecContext, name : String) -> Int {
  let mut current = name
  let mut depth = 0

  while depth < 32 {
    let raw = self.env.get(current).unwrap_or("")
    let trimmed = arith_trim(raw)
    if trimmed.length() == 0 {
      return 0
    }

    if arith_is_identifier_text(trimmed) && trimmed != current {
      current = trimmed
      depth += 1
      continue
    }

    return self.arith_parse_value_text(trimmed)
  }

  0
}

fn ExecContext::arith_get_array_elem(
  self : ExecContext,
  name : String,
  index : Int
) -> Int {
  if index < 0 {
    return 0
  }

  let key = name + "[" + index.to_string() + "]"
  match self.env.get(key) {
    Some(v) => return self.arith_parse_value_text(v)
    None => ()
  }

  let raw = self.env.get(name).unwrap_or("")
  let trimmed = arith_trim(raw)
  if trimmed.length() >= 2 &&
    trimmed[0] == '(' &&
    trimmed[trimmed.length() - 1] == ')' {
    let inner = trimmed.substring(start=1, end=trimmed.length() - 1)
    let parts = split_by_whitespace(inner)
    if index < parts.length() {
      return self.arith_parse_value_text(parts[index])
    }
  }

  0
}

fn ExecContext::arith_set_target(
  self : ExecContext,
  target : ArithTarget,
  value : Int,
  execute : Bool
) -> Unit {
  if not(execute) {
    return
  }

  match target {
    NoTarget => ()
    Var(name) => self.env[name] = value.to_string()
    ArrayElem(name, index) => {
      if index < 0 {
        return
      }
      let key = name + "[" + index.to_string() + "]"
      self.env[key] = value.to_string()
      if index == 0 {
        self.env[name] = value.to_string()
      }
    }
  }
}

fn ExecContext::arith_parse_primary(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  match p.peek() {
    Some(tok) => {
      if tok == "(" {
        ignore(p.advance())
        let result = self.arith_parse_comma(p, execute)
        ignore(p.match_tok(")"))
        return arith_plain(result.value)
      }

      ignore(p.advance())

      if arith_is_identifier_text(tok) {
        if p.match_tok("[") {
          let idx_expr = self.arith_parse_comma(p, execute)
          ignore(p.match_tok("]"))
          let idx = idx_expr.value
          let value = self.arith_get_array_elem(tok, idx)
          return arith_with_target(value, ArrayElem(tok, idx))
        }
        let value = self.arith_get_var_value(tok)
        return arith_with_target(value, Var(tok))
      }

      match arith_parse_number_literal(tok) {
        Some(v) => arith_plain(v)
        None => arith_plain(parse_int_str(tok))
      }
    }
    None => arith_plain(0)
  }
}

fn ExecContext::arith_parse_postfix(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut value = self.arith_parse_primary(p, execute)

  while true {
    if p.match_tok("++") {
      let old = value.value
      let newv = old + 1
      self.arith_set_target(value.target, newv, execute)
      value = arith_plain(old)
      continue
    }
    if p.match_tok("--") {
      let old = value.value
      let newv = old - 1
      self.arith_set_target(value.target, newv, execute)
      value = arith_plain(old)
      continue
    }
    break
  }

  value
}

fn ExecContext::arith_parse_unary(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  match p.peek() {
    Some(op) => {
      if op == "+" || op == "-" || op == "!" || op == "~" || op == "++" || op == "--" {
        ignore(p.advance())
        let operand = self.arith_parse_unary(p, execute)
        match op {
          "+" => arith_plain(operand.value)
          "-" => arith_plain(-operand.value)
          "!" => arith_plain(if operand.value == 0 { 1 } else { 0 })
          "~" => arith_plain(operand.value.lnot())
          "++" => {
            let newv = operand.value + 1
            match operand.target {
              NoTarget => arith_plain(operand.value)
              _ => {
                self.arith_set_target(operand.target, newv, execute)
                arith_plain(newv)
              }
            }
          }
          "--" => {
            let newv = operand.value - 1
            match operand.target {
              NoTarget => arith_plain(operand.value)
              _ => {
                self.arith_set_target(operand.target, newv, execute)
                arith_plain(newv)
              }
            }
          }
          _ => arith_plain(operand.value)
        }
      } else {
        self.arith_parse_postfix(p, execute)
      }
    }
    None => self.arith_parse_postfix(p, execute)
  }
}

fn ExecContext::arith_parse_mul(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_unary(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "*" || op == "/" || op == "%" {
          ignore(p.advance())
          let right = self.arith_parse_unary(p, execute)
          let value = match op {
            "*" => left.value * right.value
            "/" => if right.value == 0 { 0 } else { left.value / right.value }
            "%" => if right.value == 0 { 0 } else { left.value % right.value }
            _ => left.value
          }
          left = arith_plain(value)
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_add(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_mul(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "+" || op == "-" {
          ignore(p.advance())
          let right = self.arith_parse_mul(p, execute)
          let value = if op == "+" {
            left.value + right.value
          } else {
            left.value - right.value
          }
          left = arith_plain(value)
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_shift(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_add(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "<<" || op == ">>" {
          ignore(p.advance())
          let right = self.arith_parse_add(p, execute)
          let value = if op == "<<" {
            arith_shift_left(left.value, right.value)
          } else {
            arith_shift_right(left.value, right.value)
          }
          left = arith_plain(value)
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_rel(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_shift(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "<" || op == "<=" || op == ">" || op == ">=" {
          ignore(p.advance())
          let right = self.arith_parse_shift(p, execute)
          let ok = if op == "<" {
            left.value < right.value
          } else if op == "<=" {
            left.value <= right.value
          } else if op == ">" {
            left.value > right.value
          } else {
            left.value >= right.value
          }
          left = arith_plain(if ok { 1 } else { 0 })
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_eq(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_rel(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "==" || op == "!=" {
          ignore(p.advance())
          let right = self.arith_parse_rel(p, execute)
          let ok = if op == "==" {
            left.value == right.value
          } else {
            left.value != right.value
          }
          left = arith_plain(if ok { 1 } else { 0 })
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_bitand(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_eq(p, execute)
  while p.match_tok("&") {
    let right = self.arith_parse_eq(p, execute)
    left = arith_plain(left.value.land(right.value))
  }
  left
}

fn ExecContext::arith_parse_bitxor(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_bitand(p, execute)
  while p.match_tok("^") {
    let right = self.arith_parse_bitand(p, execute)
    left = arith_plain(left.value.lxor(right.value))
  }
  left
}

fn ExecContext::arith_parse_bitor(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_bitxor(p, execute)
  while p.match_tok("|") {
    let right = self.arith_parse_bitxor(p, execute)
    left = arith_plain(left.value.lor(right.value))
  }
  left
}

fn ExecContext::arith_parse_logand(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_bitor(p, execute)

  while p.match_tok("&&") {
    if left.value != 0 {
      let right = self.arith_parse_bitor(p, execute)
      left = arith_plain(if right.value != 0 { 1 } else { 0 })
    } else {
      ignore(self.arith_parse_bitor(p, false))
      left = arith_plain(0)
    }
  }

  left
}

fn ExecContext::arith_parse_logor(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_logand(p, execute)

  while p.match_tok("||") {
    if left.value != 0 {
      ignore(self.arith_parse_logand(p, false))
      left = arith_plain(1)
    } else {
      let right = self.arith_parse_logand(p, execute)
      left = arith_plain(if right.value != 0 { 1 } else { 0 })
    }
  }

  left
}

fn ExecContext::arith_parse_ternary(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let cond = self.arith_parse_logor(p, execute)
  if not(p.match_tok("?")) {
    return cond
  }

  if cond.value != 0 {
    let then_v = self.arith_parse_comma(p, execute)
    if p.match_tok(":") {
      ignore(self.arith_parse_ternary(p, false))
    }
    arith_plain(then_v.value)
  } else {
    ignore(self.arith_parse_comma(p, false))
    if p.match_tok(":") {
      let else_v = self.arith_parse_ternary(p, execute)
      arith_plain(else_v.value)
    } else {
      arith_plain(0)
    }
  }
}

fn ExecContext::arith_parse_assignment(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let left = self.arith_parse_ternary(p, execute)
  let op = match p.peek() {
    Some(v) => v
    None => return left
  }
  if not(arith_is_assignment_op(op)) {
    return left
  }

  ignore(p.advance())
  let right = self.arith_parse_assignment(p, execute)

  let newv = match op {
    "=" => right.value
    "+=" => left.value + right.value
    "-=" => left.value - right.value
    "*=" => left.value * right.value
    "/=" => if right.value == 0 { 0 } else { left.value / right.value }
    "%=" => if right.value == 0 { 0 } else { left.value % right.value }
    "&=" => left.value.land(right.value)
    "|=" => left.value.lor(right.value)
    "^=" => left.value.lxor(right.value)
    "<<=" => arith_shift_left(left.value, right.value)
    ">>=" => arith_shift_right(left.value, right.value)
    _ => right.value
  }

  self.arith_set_target(left.target, newv, execute)
  arith_plain(newv)
}

fn ExecContext::arith_parse_comma(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut result = self.arith_parse_assignment(p, execute)
  while p.match_tok(",") {
    result = self.arith_parse_assignment(p, execute)
  }
  result
}

fn arith_is_special_var_char(ch : Char) -> Bool {
  ch == '?' ||
  ch == '!' ||
  ch == '$' ||
  ch == '#' ||
  ch == '@' ||
  ch == '*' ||
  ch == '-'
}

fn ExecContext::arith_expand_dollar_refs(self : ExecContext, raw : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < raw.length() {
    let ch = raw[i].to_int().unsafe_to_char()
    if ch == '$' && i + 1 < raw.length() {
      let next = raw[i + 1].to_int().unsafe_to_char()
      if arith_is_ident_start(next) {
        let mut j = i + 2
        while j < raw.length() && arith_is_ident_char(raw[j].to_int().unsafe_to_char()) {
          j += 1
        }
        let name = raw.substring(start=i + 1, end=j)
        out.write_string(self.expand_variable(name))
        i = j
        continue
      }
      if arith_is_digit(next) {
        let mut j = i + 2
        while j < raw.length() && arith_is_digit(raw[j].to_int().unsafe_to_char()) {
          j += 1
        }
        let name = raw.substring(start=i + 1, end=j)
        out.write_string(self.expand_variable(name))
        i = j
        continue
      }
      if arith_is_special_var_char(next) {
        let name = raw.substring(start=i + 1, end=i + 2)
        out.write_string(self.expand_variable(name))
        i += 2
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn ExecContext::eval_arith_raw(self : ExecContext, raw : String) -> Int {
  let expanded = self.arith_expand_dollar_refs(raw)
  let tokens = arith_tokenize(expanded)
  if tokens.length() == 0 {
    return 0
  }
  let parser : ArithParser = { tokens, pos: 0 }
  let result = self.arith_parse_comma(parser, true)
  result.value
}

fn ExecContext::eval_arith(self : ExecContext, expr : @ast.ArithExpr) -> Int {
  match expr {
    @ast.ArithExpr::Num(n) => n
    @ast.ArithExpr::Var(name) => self.arith_get_var_value(name)
    @ast.ArithExpr::BinOp(op, left, right) => {
      let l = self.eval_arith(left)
      let r = self.eval_arith(right)
      match op {
        @ast.ArithBinOp::Add => l + r
        @ast.ArithBinOp::Sub => l - r
        @ast.ArithBinOp::Mul => l * r
        @ast.ArithBinOp::Div => if r == 0 { 0 } else { l / r }
        @ast.ArithBinOp::Mod => if r == 0 { 0 } else { l % r }
        @ast.ArithBinOp::Eq => if l == r { 1 } else { 0 }
        @ast.ArithBinOp::Ne => if l != r { 1 } else { 0 }
        @ast.ArithBinOp::Lt => if l < r { 1 } else { 0 }
        @ast.ArithBinOp::Le => if l <= r { 1 } else { 0 }
        @ast.ArithBinOp::Gt => if l > r { 1 } else { 0 }
        @ast.ArithBinOp::Ge => if l >= r { 1 } else { 0 }
        @ast.ArithBinOp::LogicalAnd => if l != 0 && r != 0 { 1 } else { 0 }
        @ast.ArithBinOp::LogicalOr => if l != 0 || r != 0 { 1 } else { 0 }
        @ast.ArithBinOp::BitwiseAnd => l.land(r)
        @ast.ArithBinOp::BitwiseOr => l.lor(r)
        @ast.ArithBinOp::BitwiseXor => l.lxor(r)
        @ast.ArithBinOp::ShiftLeft => l << r
        @ast.ArithBinOp::ShiftRight => l >> r
        @ast.ArithBinOp::Pow => int_pow(l, r)
      }
    }
    @ast.ArithExpr::UnaryOp(op, operand) => {
      let v = self.eval_arith(operand)
      match op {
        @ast.ArithUnaryOp::Negate => -v
        @ast.ArithUnaryOp::LogicalNot => if v == 0 { 1 } else { 0 }
        @ast.ArithUnaryOp::BitwiseNot => v.lnot()
        @ast.ArithUnaryOp::PreIncr | @ast.ArithUnaryOp::PostIncr => v + 1
        @ast.ArithUnaryOp::PreDecr | @ast.ArithUnaryOp::PostDecr => v - 1
      }
    }
    @ast.ArithExpr::Assign(name, value_expr) => {
      let v = self.eval_arith(value_expr)
      self.env[name] = v.to_string()
      v
    }
    @ast.ArithExpr::Ternary(cond, then_expr, else_expr) => {
      let c = self.eval_arith(cond)
      if c != 0 {
        self.eval_arith(then_expr)
      } else {
        self.eval_arith(else_expr)
      }
    }
    @ast.ArithExpr::Raw(raw) => self.eval_arith_raw(raw)
  }
}

// ============================================================================
// Word Splitting
// ============================================================================

fn ExecContext::word_split(
  self : ExecContext,
  s : String
) -> Array[String] {
  if s.length() == 0 {
    return [""]
  }
  let ifs = self.env.get("IFS").unwrap_or(" \t\n")
  if ifs.length() == 0 {
    return [s]
  }
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if is_ifs_char(ch, ifs) {
      let word = buf.to_string()
      if word.length() > 0 {
        result.push(word)
        buf.reset()
      }
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  if result.length() == 0 {
    return [s]
  }
  result
}

fn is_ifs_char(ch : Char, ifs : String) -> Bool {
  for i = 0; i < ifs.length(); i = i + 1 {
    if ifs[i].to_int().unsafe_to_char() == ch {
      return true
    }
  }
  false
}

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
      let content = input.substring(start=start + 1, end=end_)
      let options = parse_brace_options(content)
      if options.length() == 0 {
        out.push(input)
        return
      }
      let prefix = input.substring(start=0, end=start)
      let suffix = input.substring(start=end_ + 1)
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
      parts.push(content.substring(start=start, end=i))
      start = i + 1
      has_comma = true
    }
  }

  if has_comma {
    parts.push(content.substring(start=start, end=content.length()))
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
        None => if end_num >= start_num { 1 } else { -1 }
      }
      if step == 0 {
        return []
      }
      return generate_numeric_range(start_num, end_num, step)
    }
    _ => ()
  }

  if parts[0].length() == 1 && parts[1].length() == 1 {
    let start_ch = parts[0][0].to_int()
    let end_ch = parts[1][0].to_int()
    let step = match step_opt {
      Some(v) => v
      None => if end_ch >= start_ch { 1 } else { -1 }
    }
    if step == 0 {
      return []
    }
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
      parts.push(content.substring(start=start, end=i))
      start = i + 2
      i += 2
      continue
    }
    i += 1
  }
  parts.push(content.substring(start=start, end=content.length()))
  parts
}

fn parse_signed_int(text : String) -> Int? {
  if text.length() == 0 {
    return None
  }
  let mut sign = 1
  let mut i = 0
  if text[0] == '-' {
    sign = -1
    i = 1
  } else if text[0] == '+' {
    i = 1
  }
  if i >= text.length() {
    return None
  }
  let mut value = 0
  while i < text.length() {
    let ch = text[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    i += 1
  }
  Some(value * sign)
}

fn generate_numeric_range(start_num : Int, end_num : Int, step : Int) -> Array[String] {
  let out : Array[String] = []
  let mut current = start_num
  while true {
    if out.length() >= brace_expansion_result_limit {
      break
    }
    if step > 0 {
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
    self.stderr_buf.write_string("moonbash: \{message}\n")
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
  "__MOONBASH_ARRAY_COUNT__" + name
}

fn array_count_var_name(name : String) -> String? {
  if name.length() >= 3 {
    let suffix = name.substring(start=name.length() - 3, end=name.length())
    if suffix == "[@]" || suffix == "[*]" {
      let base = name.substring(start=0, end=name.length() - 3)
      return Some(expansion_array_count_storage_key(base))
    }
  }
  None
}

fn indirection_array_keys_name(name : String) -> String? {
  if name.length() >= 3 {
    let suffix = name.substring(start=name.length() - 3, end=name.length())
    if suffix == "[@]" || suffix == "[*]" {
      let base = name.substring(start=0, end=name.length() - 3)
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
    let prefix = name.substring(start=0, end=name.length() - 1)
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

  let base = name.substring(start=0, end=bracket)
  if not(is_expand_var_base_name(base)) {
    return None
  }

  let index = name.substring(start=bracket + 1, end=name.length() - 1)
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

  s.substring(start=start, end=end_)
}

fn strip_wrapping_quotes(text : String) -> String {
  if text.length() >= 2 {
    let first = text[0].to_int().unsafe_to_char()
    let last = text[text.length() - 1].to_int().unsafe_to_char()
    if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
      return text.substring(start=1, end=text.length() - 1)
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
      let key = env_key.substring(start=prefix.length(), end=env_key.length() - 1)
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
        segments.push(path.substring(start=start, end=i))
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
      return abs_path.substring(start=1)
    }
    return abs_path
  }
  let prefix = self.cwd + "/"
  if starts_with(abs_path, prefix) {
    return abs_path.substring(start=prefix.length())
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
      let prefix = value.substring(start=0, end=i)
      if simple_pattern_match(prefix, pattern) {
        return value.substring(start=i)
      }
    }
    value
  } else {
    // Try shortest match from start
    for i = 0; i <= value.length(); i = i + 1 {
      let prefix = value.substring(start=0, end=i)
      if simple_pattern_match(prefix, pattern) {
        return value.substring(start=i)
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
      let suffix = value.substring(start=i)
      if simple_pattern_match(suffix, pattern) {
        return value.substring(start=0, end=i)
      }
    }
    value
  } else {
    // Try shortest match from end
    for i = value.length(); i >= 0; i = i - 1 {
      let suffix = value.substring(start=i)
      if simple_pattern_match(suffix, pattern) {
        return value.substring(start=0, end=i)
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
        let prefix = value.substring(start=0, end=i)
        if simple_pattern_match(prefix, pattern) {
          return replacement + value.substring(start=i)
        }
      }
      value
    }
    @ast.ReplaceMode::Suffix => {
      // Replace only if pattern matches at end
      for i = value.length(); i >= 0; i = i - 1 {
        let suffix = value.substring(start=i)
        if simple_pattern_match(suffix, pattern) {
          return value.substring(start=0, end=i) + replacement
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
      let substr = value.substring(start=i, end=j)
      if simple_pattern_match(substr, pattern) {
        return value.substring(start=0, end=i) + replacement + value.substring(start=j)
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
      let substr = value.substring(start=i, end=j)
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
  s.substring(start=0, end=end)
}

fn int_pow(base : Int, exp : Int) -> Int {
  if exp <= 0 {
    return 1
  }
  let mut result = 1
  for _i = 0; _i < exp; _i = _i + 1 {
    result *= base
  }
  result
}
