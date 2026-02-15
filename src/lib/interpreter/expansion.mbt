// MoonBash Interpreter - Word Expansion
// Handles variable expansion, command substitution, word splitting, etc.

// ============================================================================
// Word Expansion
// ============================================================================

/// Expand a Word into an array of strings (after word splitting).
fn ExecContext::expand_word(self : ExecContext, word : @ast.Word) -> Array[String] {
  let expanded = self.expand_word_parts(word.parts)
  if expanded.length() == 0 {
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

  if not(has_splittable_expansion) {
    [expanded]
  } else {
    self.word_split(expanded)
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
    _ => self.env.get(name).unwrap_or("")
  }
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
      let value = self.expand_variable(name)
      value.length().to_string()
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
      let indirect_name = self.expand_variable(name)
      self.expand_variable(indirect_name)
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
  // Save current I/O state
  let saved_stdout = self.stdout_buf
  let saved_stderr = self.stderr_buf
  let saved_stdin = self.stdin_buf

  // Execute in a sub-context
  self.stdout_buf = StringBuilder::new()
  self.stderr_buf = StringBuilder::new()

  let parsed = try {
    @parser.parse(script_str)
  } catch {
    @ast.BashError(_msg) => {
      self.stdout_buf = saved_stdout
      self.stderr_buf = saved_stderr
      self.stdin_buf = saved_stdin
      return ""
    }
  }
  self.execute_script(parsed)

  let output = self.stdout_buf.to_string()

  // Restore I/O
  self.stdout_buf = saved_stdout
  self.stderr_buf = saved_stderr
  self.stdin_buf = saved_stdin

  // Strip trailing newlines (bash behavior)
  strip_trailing_newlines(output)
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

fn ExecContext::eval_arith(self : ExecContext, expr : @ast.ArithExpr) -> Int {
  match expr {
    @ast.ArithExpr::Num(n) => n
    @ast.ArithExpr::Var(name) => {
      let value = self.expand_variable(name)
      parse_int_str(value)
    }
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
        @ast.ArithBinOp::ShiftRight => l.lsr(r)
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
