// MoonBash Lexer
// Character-by-character scanner that tokenizes shell scripts.

// ============================================================================
// Constants
// ============================================================================

let max_input_size : Int = 10 * 1024 * 1024 // 10 MB

let max_tokens : Int = 100_000

// ============================================================================
// String Character Access Helper
// ============================================================================

/// Get character at index from a string, converting UInt16 to Char.
fn char_at(s : String, i : Int) -> Char {
  s[i].to_int().unsafe_to_char()
}

// ============================================================================
// Lexer State
// ============================================================================

pub(all) struct Lexer {
  source : String
  mut pos : Int
  mut tokens : Array[@ast.Token]
}

// ============================================================================
// Public API
// ============================================================================

/// Tokenize a shell script string into an array of tokens.
pub fn tokenize(input : String) -> Array[@ast.Token] raise @ast.BashError {
  if input.length() > max_input_size {
    raise @ast.BashError("input exceeds maximum size of 10MB")
  }
  let lexer : Lexer = { source: input, pos: 0, tokens: [] }
  lexer.scan_tokens()
  lexer.tokens
}

// ============================================================================
// Character Helpers
// ============================================================================

fn Lexer::peek(self : Lexer) -> Char {
  if self.pos >= self.source.length() {
    '\u0000'
  } else {
    char_at(self.source, self.pos)
  }
}

fn Lexer::peek_at(self : Lexer, offset : Int) -> Char {
  let idx = self.pos + offset
  if idx >= self.source.length() {
    '\u0000'
  } else {
    char_at(self.source, idx)
  }
}

fn Lexer::advance(self : Lexer) -> Char {
  let ch = self.peek()
  self.pos += 1
  ch
}

fn Lexer::at_end(self : Lexer) -> Bool {
  self.pos >= self.source.length()
}

fn Lexer::emit(self : Lexer, tok : @ast.Token) -> Unit raise @ast.BashError {
  if self.tokens.length() >= max_tokens {
    raise @ast.BashError("token count exceeds maximum of 100000")
  }
  self.tokens.push(tok)
}

// ============================================================================
// Character Classification
// ============================================================================

fn is_whitespace(ch : Char) -> Bool {
  ch == ' ' || ch == '\t'
}

fn is_metachar(ch : Char) -> Bool {
  ch == '|' ||
  ch == '&' ||
  ch == ';' ||
  ch == '(' ||
  ch == ')' ||
  ch == '<' ||
  ch == '>' ||
  ch == '\n' ||
  ch == ' ' ||
  ch == '\t'
}

fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn is_name_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '_'
}

fn is_name_char(ch : Char) -> Bool {
  is_name_start(ch) || is_digit(ch)
}

// ============================================================================
// Reserved Words
// ============================================================================

fn lookup_reserved(word : String) -> @ast.Token? {
  match word {
    "if" => Some(@ast.Token::If)
    "then" => Some(@ast.Token::Then)
    "elif" => Some(@ast.Token::Elif)
    "else" => Some(@ast.Token::Else)
    "fi" => Some(@ast.Token::Fi)
    "for" => Some(@ast.Token::For)
    "while" => Some(@ast.Token::While)
    "until" => Some(@ast.Token::Until)
    "do" => Some(@ast.Token::Do)
    "done" => Some(@ast.Token::Done)
    "case" => Some(@ast.Token::Case)
    "esac" => Some(@ast.Token::Esac)
    "in" => Some(@ast.Token::In)
    "function" => Some(@ast.Token::Function)
    "select" => Some(@ast.Token::Select)
    "time" => Some(@ast.Token::Time)
    "!" => Some(@ast.Token::Bang)
    _ => None
  }
}

// ============================================================================
// Main Scanning Loop
// ============================================================================

fn Lexer::scan_tokens(self : Lexer) -> Unit raise @ast.BashError {
  while not(self.at_end()) {
    let ch = self.peek()

    if is_whitespace(ch) {
      self.pos += 1
      continue
    }

    if ch == '\n' {
      self.advance() |> ignore
      self.emit(@ast.Token::Newline)
      continue
    }

    if ch == '#' {
      self.skip_comment()
      continue
    }

    // Operators and metacharacters
    if self.try_scan_operator() {
      continue
    }

    // Quoted strings and words
    self.scan_word()
  }
  self.emit(@ast.Token::EOF)
}

// ============================================================================
// Comment Handling
// ============================================================================

fn Lexer::skip_comment(self : Lexer) -> Unit {
  while not(self.at_end()) && self.peek() != '\n' {
    self.pos += 1
  }
}

// ============================================================================
// Operator Scanning
// ============================================================================

fn Lexer::try_scan_operator(self : Lexer) -> Bool raise @ast.BashError {
  let ch = self.peek()

  match ch {
    '|' => {
      self.pos += 1
      if self.peek() == '|' {
        self.pos += 1
        self.emit(@ast.Token::Or)
      } else if self.peek() == '&' {
        self.pos += 1
        self.emit(@ast.Token::PipeAnd)
      } else {
        self.emit(@ast.Token::Pipe)
      }
      true
    }
    '&' => {
      self.pos += 1
      if self.peek() == '&' {
        self.pos += 1
        self.emit(@ast.Token::And)
      } else if self.peek() == '>' {
        self.pos += 1
        if self.peek() == '>' {
          self.pos += 1
          self.emit(@ast.Token::RedirectAndAppend)
        } else {
          self.emit(@ast.Token::RedirectAndOut)
        }
      } else {
        self.emit(@ast.Token::Ampersand)
      }
      true
    }
    ';' => {
      self.pos += 1
      if self.peek() == ';' {
        self.pos += 1
        self.emit(@ast.Token::Semi)
        self.emit(@ast.Token::Semi)
      } else {
        self.emit(@ast.Token::Semi)
      }
      true
    }
    '(' => {
      self.pos += 1
      self.emit(@ast.Token::LeftParen)
      true
    }
    ')' => {
      self.pos += 1
      self.emit(@ast.Token::RightParen)
      true
    }
    '{' => {
      self.pos += 1
      self.emit(@ast.Token::LeftBrace)
      true
    }
    '}' => {
      self.pos += 1
      self.emit(@ast.Token::RightBrace)
      true
    }
    '<' => {
      self.scan_redirect_in()
      true
    }
    '>' => {
      self.scan_redirect_out()
      true
    }
    _ => false
  }
}

// ============================================================================
// Redirection Scanning
// ============================================================================

fn Lexer::scan_redirect_in(self : Lexer) -> Unit raise @ast.BashError {
  self.pos += 1 // consume '<'
  match self.peek() {
    '<' => {
      self.pos += 1
      if self.peek() == '<' {
        self.pos += 1
        self.emit(@ast.Token::HereString)
      } else if self.peek() == '-' {
        self.pos += 1
        self.emit(@ast.Token::HereDocStrip)
      } else {
        self.emit(@ast.Token::HereDoc)
      }
    }
    '&' => {
      self.pos += 1
      self.emit(@ast.Token::DupIn)
    }
    '>' => {
      self.pos += 1
      self.emit(@ast.Token::RedirectInOut)
    }
    _ => self.emit(@ast.Token::RedirectIn)
  }
}

fn Lexer::scan_redirect_out(self : Lexer) -> Unit raise @ast.BashError {
  self.pos += 1 // consume '>'
  match self.peek() {
    '>' => {
      self.pos += 1
      self.emit(@ast.Token::RedirectAppend)
    }
    '|' => {
      self.pos += 1
      self.emit(@ast.Token::RedirectClobber)
    }
    '&' => {
      self.pos += 1
      self.emit(@ast.Token::DupOut)
    }
    _ => self.emit(@ast.Token::RedirectOut)
  }
}

// ============================================================================
// Word Scanning
// ============================================================================

fn Lexer::scan_word(self : Lexer) -> Unit raise @ast.BashError {
  let buf = StringBuilder::new()

  while not(self.at_end()) {
    let ch = self.peek()

    if is_metachar(ch) {
      break
    }

    match ch {
      '\'' => {
        self.scan_single_quote(buf)
      }
      '"' => {
        self.scan_double_quote(buf)
      }
      '\\' => {
        self.pos += 1
        if not(self.at_end()) {
          buf.write_char(self.advance())
        }
      }
      _ => {
        buf.write_char(self.advance())
      }
    }
  }

  let word = buf.to_string()
  if word.length() == 0 {
    return
  }

  // Check for fd number before redirect
  if is_all_digits(word) && not(self.at_end()) {
    let next = self.peek()
    if next == '<' || next == '>' {
      let num = parse_int(word)
      self.emit(@ast.Token::FdNumber(num))
      return
    }
  }

  // Check for assignment: NAME=VALUE or NAME+=VALUE
  match try_split_assignment(word) {
    Some((name, value, _append)) => {
      self.emit(@ast.Token::AssignmentWord(name, value))
      return
    }
    None => ()
  }

  // Check for reserved word
  match lookup_reserved(word) {
    Some(tok) => self.emit(tok)
    None => {
      if is_all_digits(word) {
        self.emit(@ast.Token::Number(parse_int(word)))
      } else {
        self.emit(@ast.Token::Word(word))
      }
    }
  }
}

fn Lexer::scan_single_quote(self : Lexer, buf : StringBuilder) -> Unit raise @ast.BashError {
  self.pos += 1 // skip opening quote
  while not(self.at_end()) {
    let ch = self.advance()
    if ch == '\'' {
      return
    }
    buf.write_char(ch)
  }
  raise @ast.BashError("unterminated single quote")
}

fn Lexer::scan_double_quote(self : Lexer, buf : StringBuilder) -> Unit raise @ast.BashError {
  self.pos += 1 // skip opening quote
  while not(self.at_end()) {
    let ch = self.advance()
    match ch {
      '"' => return
      '\\' => {
        if not(self.at_end()) {
          let next = self.peek()
          if next == '$' || next == '`' || next == '"' || next == '\\' || next == '\n' {
            buf.write_char(self.advance())
          } else {
            buf.write_char('\\')
          }
        } else {
          buf.write_char('\\')
        }
      }
      _ => buf.write_char(ch)
    }
  }
  raise @ast.BashError("unterminated double quote")
}

// ============================================================================
// String Utilities
// ============================================================================

/// Extract a substring by charcode (UTF-16) indices.
fn substr(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end && i < s.length(); i = i + 1 {
    buf.write_char(char_at(s, i))
  }
  buf.to_string()
}

fn is_all_digits(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    if not(is_digit(char_at(s, i))) {
      return false
    }
  }
  true
}

fn parse_int(s : String) -> Int {
  let mut result = 0
  for i = 0; i < s.length(); i = i + 1 {
    result = result * 10 + (char_at(s, i).to_int() - '0'.to_int())
  }
  result
}

/// Try to split a word into an assignment: NAME=VALUE or NAME+=VALUE.
/// Returns Some((name, value, append)) or None.
fn try_split_assignment(word : String) -> (String, String, Bool)? {
  let mut eq_pos = -1
  for i = 0; i < word.length(); i = i + 1 {
    let ch = char_at(word, i)
    if ch == '=' {
      eq_pos = i
      break
    }
    if not(is_name_char(ch)) {
      return None
    }
  }
  if eq_pos <= 0 {
    return None
  }
  let name_end = eq_pos
  let append = eq_pos >= 2 && char_at(word, eq_pos - 1) == '+'
  let actual_name_end = if append { name_end - 1 } else { name_end }
  if actual_name_end == 0 {
    return None
  }
  if not(is_name_start(char_at(word, 0))) {
    return None
  }
  for i = 1; i < actual_name_end; i = i + 1 {
    if not(is_name_char(char_at(word, i))) {
      return None
    }
  }
  let name = substr(word, 0, actual_name_end)
  let value = substr(word, eq_pos + 1, word.length())
  Some((name, value, append))
}
