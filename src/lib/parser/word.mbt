// moon_bash Parser - Word/Expansion Parsing
// Handles parsing of word content into WordPart arrays.
// Recognizes $VAR, ${VAR}, ${VAR:-default}, $(cmd), $((expr)), etc.

/// Helper to get character at index.
fn wchar_at(s : String, i : Int) -> Char {
  s[i].to_int().unsafe_to_char()
}

/// Parse a word content string into an array of WordParts.
pub fn parse_word_parts(s : String) -> Array[@ast.WordPart] {
  parse_word_parts_with_context(
    s,
    in_double_quote=false,
    parse_raw_quotes=false,
  )
}

fn parse_word_parts_with_context(
  s : String,
  in_double_quote~ : Bool = false,
  parse_raw_quotes~ : Bool = false
) -> Array[@ast.WordPart] {
  let parts : Array[@ast.WordPart] = []
  let buf = StringBuilder::new()
  let mut i = 0
  let len = s.length()

  while i < len {
    let ch = wchar_at(s, i)

    if ch == '\u0002' {
      // Marker emitted by lexer for double-quoted content.
      let lit = buf.to_string()
      let locale_quote = lit.length() > 0 && wchar_at(lit, lit.length() - 1) == '$'
      if lit.length() > 0 {
        if locale_quote {
          let prefix = wsubstr(lit, 0, lit.length() - 1)
          if prefix.length() > 0 {
            parts.push(@ast.WordPart::Literal(prefix))
          }
        } else {
          parts.push(@ast.WordPart::Literal(lit))
        }
        buf.reset()
      }

      i += 1
      let quoted = StringBuilder::new()
      while i < len && wchar_at(s, i) != '\u0003' {
        quoted.write_char(wchar_at(s, i))
        i += 1
      }
      let inner_parts = parse_word_parts_with_context(
        quoted.to_string(),
        in_double_quote=true,
        parse_raw_quotes=parse_raw_quotes,
      )
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
      let normalized_quoted_text = strip_single_quote_empty_markers(quoted.to_string())
      if ansi_c_quote {
        parts.push(@ast.WordPart::Literal(decode_ansi_c_escapes(normalized_quoted_text)))
      } else {
        parts.push(@ast.WordPart::SingleQuoted(normalized_quoted_text))
      }
      continue
    } else if parse_raw_quotes &&
      ch == '\'' &&
      !(in_double_quote) &&
      has_closing_raw_single_quote(s, i + 1) {
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
      let (quoted_text, next_pos) = parse_raw_single_quoted_segment(s, i + 1, ansi_c_quote)
      let normalized_quoted_text = strip_single_quote_empty_markers(quoted_text)
      if ansi_c_quote {
        parts.push(@ast.WordPart::Literal(decode_ansi_c_escapes(normalized_quoted_text)))
      } else {
        parts.push(@ast.WordPart::SingleQuoted(normalized_quoted_text))
      }
      i = next_pos
      continue
    } else if parse_raw_quotes &&
      ch == '"' &&
      !(in_double_quote) &&
      has_closing_raw_double_quote(s, i + 1) {
      let lit = buf.to_string()
      let locale_quote = lit.length() > 0 && wchar_at(lit, lit.length() - 1) == '$'
      if lit.length() > 0 {
        if locale_quote {
          let prefix = wsubstr(lit, 0, lit.length() - 1)
          if prefix.length() > 0 {
            parts.push(@ast.WordPart::Literal(prefix))
          }
        } else {
          parts.push(@ast.WordPart::Literal(lit))
        }
        buf.reset()
      }
      let (quoted_text, next_pos) = parse_raw_double_quoted_segment(s, i + 1)
      let inner_parts = parse_word_parts_with_context(
        quoted_text,
        in_double_quote=true,
        parse_raw_quotes=parse_raw_quotes,
      )
      parts.push(@ast.WordPart::DoubleQuoted(inner_parts))
      i = next_pos
      continue
    } else if ch == '\\' {
      if i + 1 < len {
        let next = wchar_at(s, i + 1)
        if next == '\n' {
          i += 2
          continue
        }
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
        let result = parse_brace_expansion(s, i + 2, in_double_quote=in_double_quote)
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
      } else if next == '[' {
        // $[...] legacy arithmetic expansion
        let result = parse_legacy_arith_expansion(s, i + 2)
        parts.push(result.0)
        i = result.1
        continue
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
      if !(has_closing_backtick(s, i + 1)) {
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

fn has_closing_raw_single_quote(s : String, start : Int) -> Bool {
  let mut i = start
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '\'' {
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

fn has_closing_raw_double_quote(s : String, start : Int) -> Bool {
  let mut i = start
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '"' {
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

fn parse_raw_single_quoted_segment(
  s : String,
  start : Int,
  ansi_c_quote : Bool
) -> (String, Int) {
  let quoted = StringBuilder::new()
  let mut i = start
  let mut escaped = false
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '\'' {
      if !(ansi_c_quote) || !(escaped) {
        return (quoted.to_string(), i + 1)
      }
    }
    quoted.write_char(ch)
    if ansi_c_quote && ch == '\\' && !(escaped) {
      escaped = true
    } else {
      escaped = false
    }
    i += 1
  }
  (quoted.to_string(), i)
}

fn parse_raw_double_quoted_segment(s : String, start : Int) -> (String, Int) {
  let quoted = StringBuilder::new()
  let mut i = start
  while i < s.length() {
    let ch = wchar_at(s, i)
    if ch == '"' {
      return (quoted.to_string(), i + 1)
    }
    if ch == '\\' && i + 1 < s.length() {
      let next = wchar_at(s, i + 1)
      if next == '$' || next == '`' || next == '"' || next == '\\' {
        quoted.write_char(next)
        i += 2
        continue
      }
      if next == '\n' {
        i += 2
        continue
      }
      quoted.write_char('\\')
      i += 1
      continue
    }
    quoted.write_char(ch)
    i += 1
  }
  (quoted.to_string(), i)
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
      'e' | 'E' => out.write_char('\u001b')
      '?' => out.write_char('?')
      '\\' => out.write_char('\\')
      '\'' => out.write_char('\'')
      '"' => out.write_char('"')
      'c' => {
        if i + 2 < s.length() {
          let ctrl = (wchar_at(s, i + 2).to_int() & 0x1f).unsafe_to_char()
          out.write_char(ctrl)
          i += 1
        } else {
          out.write_char('\\')
          out.write_char('c')
        }
      }
      'x' => {
        let (value, consumed) = parse_hex_escape_digits(s, i + 2, 2)
        if consumed > 0 {
          out.write_char(value.unsafe_to_char())
          i += consumed
        } else {
          out.write_char('\\')
          out.write_char('x')
        }
      }
      'u' => {
        let (value, consumed) = parse_hex_escape_digits(s, i + 2, 4)
        if consumed == 4 {
          out.write_char(value.unsafe_to_char())
          i += consumed
        } else {
          out.write_char('\\')
          out.write_char('u')
        }
      }
      'U' => {
        let (value, consumed) = parse_hex_escape_digits(s, i + 2, 8)
        if consumed == 8 {
          out.write_char(value.unsafe_to_char())
          i += consumed
        } else {
          out.write_char('\\')
          out.write_char('U')
        }
      }
      _ => {
        if next >= '0' && next <= '7' {
          let (value, consumed) = parse_octal_escape_digits(s, i + 1, 3)
          out.write_char(value.unsafe_to_char())
          i += consumed - 1
        } else {
          out.write_char('\\')
          out.write_char(next)
        }
      }
    }
    i += 2
  }
  out.to_string()
}

fn parse_hex_escape_digits(s : String, start : Int, max_digits : Int) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut consumed = 0
  while i < s.length() && consumed < max_digits {
    let ch = wchar_at(s, i)
    let digit = match hex_digit_value(ch) {
      Some(d) => d
      None => break
    }
    value = value * 16 + digit
    i += 1
    consumed += 1
  }
  (value, consumed)
}

fn parse_octal_escape_digits(s : String, start : Int, max_digits : Int) -> (Int, Int) {
  let mut i = start
  let mut value = 0
  let mut consumed = 0
  while i < s.length() && consumed < max_digits {
    let ch = wchar_at(s, i)
    if ch < '0' || ch > '7' {
      break
    }
    value = value * 8 + (ch.to_int() - '0'.to_int())
    i += 1
    consumed += 1
  }
  (value, consumed)
}

fn hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    return Some(ch.to_int() - '0'.to_int())
  }
  if ch >= 'a' && ch <= 'f' {
    return Some(ch.to_int() - 'a'.to_int() + 10)
  }
  if ch >= 'A' && ch <= 'F' {
    return Some(ch.to_int() - 'A'.to_int() + 10)
  }
  None
}

fn strip_single_quote_empty_markers(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = wchar_at(s, i)
    if ch != '\u0000' {
      out.write_char(ch)
    }
  }
  out.to_string()
}

/// Parse parameter name end, allowing optional array subscripts: name[...].
fn parse_param_name_end(content : String) -> Int {
  let len = content.length()
  if len == 0 {
    return 0
  }
  if !(is_var_start(wchar_at(content, 0))) {
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
    // Malformed subscript, fallback to base name only.
    if depth > 0 {
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
fn parse_brace_expansion(
  s : String,
  start : Int,
  in_double_quote~ : Bool = false
) -> (@ast.WordPart, Int) {
  // Find matching closing brace (simplified: no nested braces)
  let mut depth = 1
  let mut i = start
  let mut in_single = false
  let mut in_double = false
  let mut escaped = false
  while i < s.length() && depth > 0 {
    let ch = wchar_at(s, i)

    if escaped {
      escaped = false
      if depth > 0 {
        i += 1
      }
      continue
    }

    if in_single {
      if ch == '\'' {
        in_single = false
      }
      if depth > 0 {
        i += 1
      }
      continue
    }

    if in_double {
      if ch == '"' {
        in_double = false
      } else if ch == '\\' {
        escaped = true
      }
      if depth > 0 {
        i += 1
      }
      continue
    }

    if ch == '\\' {
      escaped = true
      if depth > 0 {
        i += 1
      }
      continue
    }

    if ch == '\'' {
      in_single = true
      if depth > 0 {
        i += 1
      }
      continue
    }

    if ch == '"' {
      in_double = true
      if depth > 0 {
        i += 1
      }
      continue
    }

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
  let part = parse_param_expansion_content(content, in_double_quote=in_double_quote)
  (part, i)
}

/// Parse the content inside ${...} to determine expansion type.
fn parse_param_expansion_content(
  content : String,
  in_double_quote~ : Bool = false
) -> @ast.WordPart {
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
  let raw_name_end = parse_param_name_end(content)
  let name_end = if raw_name_end == 0 {
    // Special variable like ${?}, ${*}, ${@}, etc.
    if len >= 1 && is_special_var(wchar_at(content, 0)) {
      1
    } else {
      0
    }
  } else {
    raw_name_end
  }

  if name_end == 0 {
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
      let word = parse_param_operator_word(word_str, in_double_quote=in_double_quote)
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
      let word = parse_param_operator_word(word_str, in_double_quote=in_double_quote)
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Default(name, word, false))
    }
    '=' => {
      let word_str = wsubstr(content, rest_start, len)
      let word = parse_param_operator_word(word_str, in_double_quote=in_double_quote)
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Assign(name, word, false))
    }
    '?' => {
      let word_str = wsubstr(content, rest_start, len)
      let word = parse_param_operator_word(word_str, in_double_quote=in_double_quote)
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Error(name, Some(word), false))
    }
    '+' => {
      let word_str = wsubstr(content, rest_start, len)
      let word = parse_param_operator_word(word_str, in_double_quote=in_double_quote)
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Alternative(name, word, false))
    }
    '#' => {
      let greedy = rest_start < len && wchar_at(content, rest_start) == '#'
      let pat_start = if greedy { rest_start + 1 } else { rest_start }
      let pat_str = wsubstr(content, pat_start, len)
      let pat = parse_word_content_with_raw_quotes(pat_str)
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::PrefixRemove(name, pat, greedy))
    }
    '%' => {
      let greedy = rest_start < len && wchar_at(content, rest_start) == '%'
      let pat_start = if greedy { rest_start + 1 } else { rest_start }
      let pat_str = wsubstr(content, pat_start, len)
      let pat = parse_word_content_with_raw_quotes(pat_str)
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
      let pat = parse_word_content_with_raw_quotes(pat_str)
      let repl : @ast.Word? = if sep_pos < len {
        let repl_str = wsubstr(content, sep_pos + 1, len)
        Some(parse_word_content_with_raw_quotes(repl_str))
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
    '@' => {
      if rest_start + 1 == len {
        let transform = wchar_at(content, rest_start)
        if transform == 'Q' || transform == 'P' || transform == 'a' {
          return @ast.WordPart::ParameterExpansion(
            @ast.ParamExpansion::Simple(name + "@" + transform.to_string()),
          )
        }
      }
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(name))
    }
    _ => {
      // Unknown operator, treat as simple
      @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Simple(name))
    }
  }
}

fn parse_param_operator_word(
  word_str : String,
  in_double_quote~ : Bool = false
) -> @ast.Word {
  if !(in_double_quote) {
    return parse_word_content_with_raw_quotes(word_str)
  }
  let preprocessed = preprocess_param_word_in_double_quote(word_str)
  parse_word_content_with_raw_quotes(preprocessed)
}

fn parse_word_content_with_raw_quotes(s : String) -> @ast.Word {
  {
    parts:
      parse_word_parts_with_context(
        s,
        in_double_quote=false,
        parse_raw_quotes=true,
      ),
  }
}

/// In ${...:-word} parsed within outer double quotes, single quotes are literal
/// characters (LexState::DQ behavior). We preserve that by escaping them before
/// feeding the generic word parser.
fn preprocess_param_word_in_double_quote(word_str : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < word_str.length() {
    let ch = wchar_at(word_str, i)
    if ch == '\\' && i + 1 < word_str.length() {
      let next = wchar_at(word_str, i + 1)
      if next == '}' {
        out.write_char('}')
      } else {
        out.write_char('\\')
        out.write_char(next)
      }
      i += 2
      continue
    }
    if ch == '\'' {
      out.write_char('\\')
      out.write_char('\'')
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn parse_substring_spec(spec : String) -> (@ast.ArithExpr, @ast.ArithExpr?) {
  let trimmed = trim_ascii_space_word(spec)
  let colon_pos = find_substring_length_separator(trimmed)

  if colon_pos < 0 {
    let offset_text = if trimmed.length() == 0 { "0" } else { trimmed }
    return (@ast.ArithExpr::Raw(offset_text), None)
  }

  let left = trim_ascii_space_word(wsubstr(trimmed, 0, colon_pos))
  let right = trim_ascii_space_word(wsubstr(trimmed, colon_pos + 1, trimmed.length()))
  let offset_expr = @ast.ArithExpr::Raw(if left.length() == 0 { "0" } else { left })
  let length_expr = Some(@ast.ArithExpr::Raw(if right.length() == 0 { "0" } else { right }))
  (offset_expr, length_expr)
}

fn find_substring_length_separator(spec : String) -> Int {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut ternary_depth = 0
  let mut in_single = false
  let mut in_double = false
  let mut escaped = false
  let mut i = 0

  while i < spec.length() {
    let ch = wchar_at(spec, i)

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
      i += 1
      continue
    }
    if ch == ')' && paren_depth > 0 {
      paren_depth -= 1
      i += 1
      continue
    }

    if ch == '[' {
      bracket_depth += 1
      i += 1
      continue
    }
    if ch == ']' && bracket_depth > 0 {
      bracket_depth -= 1
      i += 1
      continue
    }

    if ch == '{' {
      brace_depth += 1
      i += 1
      continue
    }
    if ch == '}' && brace_depth > 0 {
      brace_depth -= 1
      i += 1
      continue
    }

    if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 {
      if ch == '?' {
        ternary_depth += 1
        i += 1
        continue
      }
      if ch == ':' {
        if ternary_depth > 0 {
          ternary_depth -= 1
          i += 1
          continue
        }
        return i
      }
    }

    i += 1
  }

  -1
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
    if !(in_single) &&
      !(in_double) &&
      !(escaped) &&
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

/// Parse $[...] legacy arithmetic expansion starting after the opening `[`.
fn parse_legacy_arith_expansion(
  s : String,
  start : Int
) -> (@ast.WordPart, Int) {
  let mut depth = 1
  let mut i = start
  let mut in_single = false
  let mut in_double = false
  let mut escaped = false

  while i < s.length() {
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

    if ch == '[' {
      depth += 1
    } else if ch == ']' {
      depth -= 1
      if depth == 0 {
        let content = wsubstr(s, start, i)
        i += 1 // skip closing ]
        return (@ast.WordPart::ArithmeticExpansion(@ast.ArithExpr::Raw(content)), i)
      }
    }

    i += 1
  }

  let content = wsubstr(s, start, s.length())
  (@ast.WordPart::ArithmeticExpansion(@ast.ArithExpr::Raw(content)), s.length())
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
    if ch == '/' || ch == ':' || ch == '{' {
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
