// moon_bash Parser - Word/Expansion Parsing
// Handles parsing of word content into WordPart arrays.
// Recognizes $VAR, ${VAR}, ${VAR:-default}, $(cmd), $((expr)), etc.

/// Helper to get character at index.
fn wchar_at(s : String, i : Int) -> Char {
  s[i].to_int().unsafe_to_char()
}

/// Parse a word content string into an array of WordParts.
pub fn parse_word_parts(s : String) -> Array[@ast.WordPart] {
  let parts : Array[@ast.WordPart] = []
  let buf = StringBuilder::new()
  let mut i = 0
  let len = s.length()

  while i < len {
    let ch = wchar_at(s, i)

    if ch == '\u0002' {
      // Marker emitted by lexer for double-quoted content.
      let lit = buf.to_string()
      if lit.length() > 0 {
        parts.push(@ast.WordPart::Literal(lit))
        buf.reset()
      }

      i += 1
      let quoted = StringBuilder::new()
      while i < len && wchar_at(s, i) != '\u0003' {
        quoted.write_char(wchar_at(s, i))
        i += 1
      }
      let inner_parts = parse_word_parts(quoted.to_string())
      parts.push(@ast.WordPart::DoubleQuoted(inner_parts))
      if i < len && wchar_at(s, i) == '\u0003' {
        i += 1
      }
      continue
    } else if ch == '\u0001' && i + 1 < len {
      // Marker emitted by lexer for single-quoted content.
      // Preserve quote semantics as dedicated SingleQuoted parts.
      let lit = buf.to_string()
      let ansi_c_quote = lit.length() > 0 && wchar_at(lit, lit.length() - 1) == '$'
      if lit.length() > 0 {
        if ansi_c_quote {
          let prefix = wsubstr(lit, 0, lit.length() - 1)
          if prefix.length() > 0 {
            parts.push(@ast.WordPart::Literal(prefix))
          }
        } else {
          parts.push(@ast.WordPart::Literal(lit))
        }
        buf.reset()
      }
      let quoted = StringBuilder::new()
      while i + 1 < len && wchar_at(s, i) == '\u0001' {
        quoted.write_char(wchar_at(s, i + 1))
        i += 2
      }
      let quoted_text = quoted.to_string()
      if ansi_c_quote {
        parts.push(@ast.WordPart::Literal(decode_ansi_c_escapes(quoted_text)))
      } else {
        parts.push(@ast.WordPart::SingleQuoted(quoted_text))
      }
      continue
    } else if ch == '\\' {
      if i + 1 < len {
        let next = wchar_at(s, i + 1)
        if next == '`' ||
          next == '$' ||
          next == '\\' ||
          next == '"' ||
          next == '\'' {
          buf.write_char(next)
          i += 2
          continue
        }
      }
      buf.write_char('\\')
      i += 1
      continue
    } else if ch == '$' && i + 1 < len {
      // Flush literal buffer
      let lit = buf.to_string()
      if lit.length() > 0 {
        parts.push(@ast.WordPart::Literal(lit))
        buf.reset()
      }

      let next = wchar_at(s, i + 1)
      if next == '{' {
        // ${...} parameter expansion
        let result = parse_brace_expansion(s, i + 2)
        parts.push(result.0)
        i = result.1
        continue
      } else if next == '(' {
        if i + 2 < len && wchar_at(s, i + 2) == '(' {
          // $((...)) arithmetic expansion
          let result = parse_arith_expansion(s, i + 3)
          parts.push(result.0)
          i = result.1
          continue
        } else {
          // $(...) command substitution
          let result = parse_cmd_substitution(s, i + 2)
          parts.push(result.0)
          i = result.1
          continue
        }
      } else if is_var_start(next) {
        // $VAR simple variable
        let result = parse_simple_variable(s, i + 1)
        parts.push(result.0)
        i = result.1
        continue
      } else if is_special_var(next) {
        // $?, $!, $$, $#, $@, $*, $0-$9, $-
        parts.push(@ast.WordPart::Variable(next.to_string()))
        i += 2
        continue
      } else {
        // Lone $, treat as literal
        buf.write_char('$')
        i += 1
        continue
      }
    } else if ch == '`' {
      if not(has_closing_backtick(s, i + 1)) {
        buf.write_char('`')
        i += 1
        continue
      }
      // Backtick command substitution
      let lit = buf.to_string()
      if lit.length() > 0 {
        parts.push(@ast.WordPart::Literal(lit))
        buf.reset()
      }
      let result = parse_backtick_substitution(s, i + 1)
      parts.push(result.0)
      i = result.1
      continue
    } else if ch == '~' && i == 0 {
      // Tilde expansion at start
      let result = parse_tilde(s, 0)
      parts.push(result.0)
      i = result.1
      continue
    } else {
      buf.write_char(ch)
      i += 1
    }
  }

  // Flush remaining literal
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    parts.push(@ast.WordPart::Literal(remaining))
  }

  // If no parts were found, add empty literal
  if parts.length() == 0 {
    parts.push(@ast.WordPart::Literal(""))
  }

  parts
}

fn has_closing_backtick(s : String, start : Int) -> Bool {
  let mut i = start
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '`' {
      return true
    }
    if ch == '\\' && i + 1 < s.length() {
      i += 2
    } else {
      i += 1
    }
  }
  false
}

// ============================================================================
// Character Classification
// ============================================================================

fn is_var_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '_'
}

fn is_var_char(ch : Char) -> Bool {
  is_var_start(ch) || (ch >= '0' && ch <= '9')
}

fn is_special_var(ch : Char) -> Bool {
  ch == '?' || ch == '!' || ch == '$' || ch == '#' ||
  ch == '@' || ch == '*' || ch == '-' ||
  (ch >= '0' && ch <= '9')
}

fn decode_ansi_c_escapes(s : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch != '\\' || i + 1 >= s.length() {
      out.write_char(ch)
      i += 1
      continue
    }

    let next = wchar_at(s, i + 1)
    match next {
      'n' => out.write_char('\n')
      't' => out.write_char('\t')
      'r' => out.write_char('\r')
      'a' => out.write_char('\u0007')
      'b' => out.write_char('\u0008')
      'f' => out.write_char('\u000c')
      'v' => out.write_char('\u000b')
      '\\' => out.write_char('\\')
      '\'' => out.write_char('\'')
      '"' => out.write_char('"')
      _ => out.write_char(next)
    }
    i += 2
  }
  out.to_string()
}

/// Parse parameter name end, allowing optional array subscripts: name[...].
fn parse_param_name_end(content : String) -> Int {
  let len = content.length()
  if len == 0 {
    return 0
  }
  if not(is_var_start(wchar_at(content, 0))) {
    return 0
  }

  let mut i = 1
  while i < len && is_var_char(wchar_at(content, i)) {
    i += 1
  }

  while i < len && wchar_at(content, i) == '[' {
    let bracket_start = i
    i += 1
    let mut depth = 1
    while i < len && depth > 0 {
      let ch = wchar_at(content, i)
      if ch == '[' {
        depth += 1
      } else if ch == ']' {
        depth -= 1
      }
      i += 1
    }
    // Malformed or empty subscript, fallback to base name only.
    if depth > 0 || i <= bracket_start + 2 {
      return bracket_start
    }
  }

  i
}

// ============================================================================
// Simple Variable: $VAR
// ============================================================================

/// Parse a simple variable name starting at pos. Returns (WordPart, next_pos).
fn parse_simple_variable(s : String, start : Int) -> (@ast.WordPart, Int) {
  let buf = StringBuilder::new()
  let mut i = start
  while i < s.length() {
    let ch = wchar_at(s, i)
    if is_var_char(ch) {
      buf.write_char(ch)
      i += 1
    } else {
      break
    }
  }
  (@ast.WordPart::Variable(buf.to_string()), i)
}

// ============================================================================
// Brace Expansion: ${...}
// ============================================================================

/// Parse ${...} starting after the opening brace.
/// Returns (WordPart, next_pos after closing brace).
fn parse_brace_expansion(s : String, start : Int) -> (@ast.WordPart, Int) {
  // Find matching closing brace (simplified: no nested braces)
  let mut depth = 1
  let mut i = start
  while i < s.length() && depth > 0 {
    let ch = wchar_at(s, i)
    if ch == '{' {
      depth += 1
    } else if ch == '}' {
      depth -= 1
    }
    if depth > 0 {
      i += 1
    }
  }

  let end = i
  let content = wsubstr(s, start, end)
  i += 1 // skip closing brace

  // Parse the content to determine expansion type
  let part = parse_param_expansion_content(content)
  (part, i)
}

/// Parse the content inside ${...} to determine expansion type.
fn parse_param_expansion_content(content : String) -> @ast.WordPart {
  let len = content.length()
  if len == 0 {
    return @ast.WordPart::Literal("")
  }

  // ${#VAR} - length
  if wchar_at(content, 0) == '#' && len > 1 {
    let name = wsubstr(content, 1, len)
    return @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Length(name))
  }

  // ${!VAR} - indirection
  if wchar_at(content, 0) == '!' && len > 1 {
    let name = wsubstr(content, 1, len)
    return @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Indirection(name))
  }

  // Find the variable name (supports optional array-style subscripts).
  let name_end = parse_param_name_end(content)

  if name_end == 0 {
    // Special variable like ${?}, ${!}, etc.
    if len >= 1 && is_special_var(wchar_at(content, 0)) {
      return @ast.WordPart::Variable(wsubstr(content, 0, 1))
    }
    return @ast.WordPart::Literal(content)
  }

  let name = wsubstr(content, 0, name_end)

  // Just ${VAR}
  if name_end >= len {
    return @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(name))
  }

  let op_char = wchar_at(content, name_end)
  let rest_start = name_end + 1

  match op_char {
    ':' => {
      if rest_start >= len {
        return @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(name))
      }
      let op2 = wchar_at(content, rest_start)
      let word_str = wsubstr(content, rest_start + 1, len)
      let word : @ast.Word = { parts: [@ast.WordPart::Literal(word_str)] }
      match op2 {
        '-' => @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Default(name, word, true))
        '=' => @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Assign(name, word, true))
        '?' => @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Error(name, Some(word), true))
        '+' => @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Alternative(name, word, true))
        _ => {
          // ${VAR:offset} or ${VAR:offset:length}
          let spec = wsubstr(content, rest_start, len)
          let (offset_expr, length_expr) = parse_substring_spec(spec)
          @ast.WordPart::ParameterExpansion(
            @ast.ParamExpansion::Substring(name, offset_expr, length_expr),
          )
        }
      }
    }
    '-' => {
      let word_str = wsubstr(content, rest_start, len)
      let word : @ast.Word = { parts: [@ast.WordPart::Literal(word_str)] }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Default(name, word, false))
    }
    '=' => {
      let word_str = wsubstr(content, rest_start, len)
      let word : @ast.Word = { parts: [@ast.WordPart::Literal(word_str)] }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Assign(name, word, false))
    }
    '?' => {
      let word_str = wsubstr(content, rest_start, len)
      let word : @ast.Word = { parts: [@ast.WordPart::Literal(word_str)] }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Error(name, Some(word), false))
    }
    '+' => {
      let word_str = wsubstr(content, rest_start, len)
      let word : @ast.Word = { parts: [@ast.WordPart::Literal(word_str)] }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Alternative(name, word, false))
    }
    '#' => {
      let greedy = rest_start < len && wchar_at(content, rest_start) == '#'
      let pat_start = if greedy { rest_start + 1 } else { rest_start }
      let pat_str = wsubstr(content, pat_start, len)
      let pat : @ast.Word = { parts: [@ast.WordPart::Literal(pat_str)] }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::PrefixRemove(name, pat, greedy))
    }
    '%' => {
      let greedy = rest_start < len && wchar_at(content, rest_start) == '%'
      let pat_start = if greedy { rest_start + 1 } else { rest_start }
      let pat_str = wsubstr(content, pat_start, len)
      let pat : @ast.Word = { parts: [@ast.WordPart::Literal(pat_str)] }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::SuffixRemove(name, pat, greedy))
    }
    '/' => {
      // ${VAR/pat/str} or ${VAR//pat/str}
      let mut mode = @ast.ReplaceMode::First
      let mut pat_start = rest_start
      if pat_start < len {
        let next = wchar_at(content, pat_start)
        if next == '/' {
          mode = @ast.ReplaceMode::All
          pat_start += 1
        } else if next == '#' {
          mode = @ast.ReplaceMode::Prefix
          pat_start += 1
        } else if next == '%' {
          mode = @ast.ReplaceMode::Suffix
          pat_start += 1
        }
      }
      // Find the separator /
      let mut sep_pos = pat_start
      while sep_pos < len && wchar_at(content, sep_pos) != '/' {
        sep_pos += 1
      }
      let pat_str = wsubstr(content, pat_start, sep_pos)
      let pat : @ast.Word = { parts: [@ast.WordPart::Literal(pat_str)] }
      let repl : @ast.Word? = if sep_pos < len {
        let repl_str = wsubstr(content, sep_pos + 1, len)
        Some({ parts: [@ast.WordPart::Literal(repl_str)] })
      } else {
        None
      }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Replace(name, pat, repl, mode))
    }
    '^' => {
      let greedy = rest_start < len && wchar_at(content, rest_start) == '^'
      let pat_start = if greedy { rest_start + 1 } else { rest_start }
      let pat : @ast.Word? = if pat_start < len {
        Some({ parts: [@ast.WordPart::Literal(wsubstr(content, pat_start, len))] })
      } else {
        None
      }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Uppercase(name, pat, greedy))
    }
    ',' => {
      let greedy = rest_start < len && wchar_at(content, rest_start) == ','
      let pat_start = if greedy { rest_start + 1 } else { rest_start }
      let pat : @ast.Word? = if pat_start < len {
        Some({ parts: [@ast.WordPart::Literal(wsubstr(content, pat_start, len))] })
      } else {
        None
      }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Lowercase(name, pat, greedy))
    }
    _ => {
      // Unknown operator, treat as simple
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(name))
    }
  }
}

fn parse_substring_spec(spec : String) -> (@ast.ArithExpr, @ast.ArithExpr?) {
  let trimmed = trim_ascii_space_word(spec)
  let mut colon_pos = -1
  for i = 0; i < trimmed.length(); i = i + 1 {
    if wchar_at(trimmed, i) == ':' {
      colon_pos = i
      break
    }
  }

  if colon_pos < 0 {
    let offset_text = if trimmed.length() == 0 { "0" } else { trimmed }
    return (@ast.ArithExpr::Raw(offset_text), None)
  }

  let left = trim_ascii_space_word(wsubstr(trimmed, 0, colon_pos))
  let right = trim_ascii_space_word(wsubstr(trimmed, colon_pos + 1, trimmed.length()))
  let offset_expr = @ast.ArithExpr::Raw(if left.length() == 0 { "0" } else { left })
  let length_expr = if right.length() == 0 {
    None
  } else {
    Some(@ast.ArithExpr::Raw(right))
  }
  (offset_expr, length_expr)
}

fn trim_ascii_space_word(s : String) -> String {
  let mut start = 0
  let mut end_ = s.length()
  while start < end_ {
    let ch = wchar_at(s, start)
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      start += 1
    } else {
      break
    }
  }
  while end_ > start {
    let ch = wchar_at(s, end_ - 1)
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      end_ -= 1
    } else {
      break
    }
  }
  wsubstr(s, start, end_)
}

// ============================================================================
// Command Substitution: $(...)
// ============================================================================

/// Parse $(...) starting after the opening paren.
fn parse_cmd_substitution(s : String, start : Int) -> (@ast.WordPart, Int) {
  let mut depth = 1
  let mut i = start
  while i < s.length() && depth > 0 {
    let ch = wchar_at(s, i)
    if ch == '(' {
      depth += 1
    } else if ch == ')' {
      depth -= 1
    }
    if depth > 0 {
      i += 1
    }
  }
  let content = wsubstr(s, start, i)
  i += 1 // skip closing paren
  (@ast.WordPart::CommandSubstitution(content), i)
}

// ============================================================================
// Arithmetic Expansion: $((...))
// ============================================================================

/// Parse $((...)) starting after the opening ((.
fn parse_arith_expansion(s : String, start : Int) -> (@ast.WordPart, Int) {
  let mut paren_depth = 0
  let mut i = start
  let mut in_single = false
  let mut in_double = false
  let mut escaped = false

  while i < s.length() {
    if not(in_single) &&
      not(in_double) &&
      not(escaped) &&
      paren_depth == 0 &&
      i + 1 < s.length() &&
      wchar_at(s, i) == ')' &&
      wchar_at(s, i + 1) == ')' {
      break
    }

    let ch = wchar_at(s, i)

    if escaped {
      escaped = false
      i += 1
      continue
    }

    if in_single {
      if ch == '\'' {
        in_single = false
      }
      i += 1
      continue
    }

    if in_double {
      if ch == '"' {
        in_double = false
      } else if ch == '\\' {
        escaped = true
      }
      i += 1
      continue
    }

    if ch == '\\' {
      escaped = true
      i += 1
      continue
    }

    if ch == '\'' {
      in_single = true
      i += 1
      continue
    }

    if ch == '"' {
      in_double = true
      i += 1
      continue
    }

    if ch == '(' {
      paren_depth += 1
    } else if ch == ')' {
      if paren_depth > 0 {
        paren_depth -= 1
      }
    }

    i += 1
  }

  let content = wsubstr(s, start, i)
  if i + 1 < s.length() {
    i += 2 // skip closing ))
  }

  (@ast.WordPart::ArithmeticExpansion(@ast.ArithExpr::Raw(content)), i)
}

// ============================================================================
// Backtick Substitution: `...`
// ============================================================================

fn parse_backtick_substitution(s : String, start : Int) -> (@ast.WordPart, Int) {
  let mut i = start
  let buf = StringBuilder::new()
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '`' {
      i += 1
      break
    }
    if ch == '\\' && i + 1 < s.length() {
      let next = wchar_at(s, i + 1)
      if next == '`' || next == '\\' || next == '$' {
        buf.write_char(next)
        i += 2
        continue
      }
    }
    buf.write_char(ch)
    i += 1
  }
  (@ast.WordPart::CommandSubstitution(buf.to_string()), i)
}

// ============================================================================
// Tilde Expansion
// ============================================================================

fn parse_tilde(s : String, start : Int) -> (@ast.WordPart, Int) {
  let mut i = start + 1 // skip ~
  let buf = StringBuilder::new()
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '/' || ch == ':' {
      break
    }
    buf.write_char(ch)
    i += 1
  }
  (@ast.WordPart::TildePrefix(buf.to_string()), i)
}

// ============================================================================
// String Utilities
// ============================================================================

/// Extract substring by character indices.
fn wsubstr(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = start
  while i < end && i < s.length() {
    buf.write_char(wchar_at(s, i))
    i += 1
  }
  buf.to_string()
}
