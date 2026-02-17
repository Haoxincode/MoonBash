// moon_bash Parser
// Recursive descent parser that converts token stream into AST.

let max_depth : Int = 100

// ============================================================================
// Parser State
// ============================================================================

pub(all) struct Parser {
  tokens : Array[@ast.Token]
  mut pos : Int
  mut depth : Int
}

// ============================================================================
// Public API
// ============================================================================

/// Parse a source string into an AST Script.
pub fn parse(input : String) -> @ast.Script raise @ast.BashError {
  let tokens = @lexer.tokenize(input)
  parse_tokens(tokens)
}

/// Parse a token array into an AST Script.
pub fn parse_tokens(tokens : Array[@ast.Token]) -> @ast.Script raise @ast.BashError {
  let parser : Parser = { tokens, pos: 0, depth: 0 }
  let script = parser.parse_script()
  parser.skip_newlines()
  if not(parser.at_end()) {
    raise @ast.BashError("syntax error near unexpected token")
  }
  script
}

// ============================================================================
// Token Helpers
// ============================================================================

fn Parser::peek(self : Parser) -> @ast.Token {
  if self.pos >= self.tokens.length() {
    @ast.Token::EOF
  } else {
    self.tokens[self.pos]
  }
}

fn Parser::advance(self : Parser) -> @ast.Token {
  let tok = self.peek()
  if self.pos < self.tokens.length() {
    self.pos += 1
  }
  tok
}

fn Parser::at_end(self : Parser) -> Bool {
  match self.peek() {
    @ast.Token::EOF => true
    _ => false
  }
}

fn Parser::expect(self : Parser, expected : @ast.Token) -> Unit raise @ast.BashError {
  let tok = self.advance()
  if tok != expected {
    raise @ast.BashError("expected \{expected}, got \{tok}")
  }
}

fn Parser::check(self : Parser, tok : @ast.Token) -> Bool {
  self.peek() == tok
}

fn Parser::match_token(self : Parser, tok : @ast.Token) -> Bool {
  if self.check(tok) {
    self.advance() |> ignore
    true
  } else {
    false
  }
}

fn Parser::skip_newlines(self : Parser) -> Unit {
  while self.check(@ast.Token::Newline) {
    self.advance() |> ignore
  }
}

fn Parser::enter_depth(self : Parser) -> Unit raise @ast.BashError {
  self.depth += 1
  if self.depth > max_depth {
    raise @ast.BashError("maximum nesting depth exceeded")
  }
}

fn Parser::leave_depth(self : Parser) -> Unit {
  self.depth -= 1
}

/// Check if current token is a word-like token (Word or a reserved word being
/// used in non-command position).
fn Parser::is_word(self : Parser) -> Bool {
  match self.peek() {
    @ast.Token::Word(_) => true
    @ast.Token::Number(_) => true
    @ast.Token::AssignmentWord(_, _, _) => true
    @ast.Token::If
    | @ast.Token::Then
    | @ast.Token::Elif
    | @ast.Token::Else
    | @ast.Token::Fi
    | @ast.Token::For
    | @ast.Token::While
    | @ast.Token::Until
    | @ast.Token::Do
    | @ast.Token::Done
    | @ast.Token::Case
    | @ast.Token::Esac
    | @ast.Token::In
    | @ast.Token::Function
    | @ast.Token::Select
    | @ast.Token::Bang
    | @ast.Token::Time => true
    _ => false
  }
}

/// Get the string value of the current token if it's word-like.
fn token_to_string(tok : @ast.Token) -> String {
  match tok {
    @ast.Token::Word(s) => s
    @ast.Token::Number(n) => n.to_string()
    @ast.Token::AssignmentWord(name, value, append) => {
      if value.length() == 0 {
        if append { name + "+=" } else { name + "=" }
      } else {
        if append { name + "+=" + value } else { name + "=" + value }
      }
    }
    @ast.Token::If => "if"
    @ast.Token::Then => "then"
    @ast.Token::Elif => "elif"
    @ast.Token::Else => "else"
    @ast.Token::Fi => "fi"
    @ast.Token::For => "for"
    @ast.Token::While => "while"
    @ast.Token::Until => "until"
    @ast.Token::Do => "do"
    @ast.Token::Done => "done"
    @ast.Token::Case => "case"
    @ast.Token::Esac => "esac"
    @ast.Token::In => "in"
    @ast.Token::Function => "function"
    @ast.Token::Select => "select"
    @ast.Token::Bang => "!"
    @ast.Token::Time => "time"
    _ => ""
  }
}

fn arith_token_to_string(tok : @ast.Token) -> String {
  match tok {
    @ast.Token::Word(s) => s
    @ast.Token::Number(n) => n.to_string()
    @ast.Token::AssignmentWord(name, value, append) =>
      if append { name + "+=" + value } else { name + "=" + value }
    @ast.Token::Pipe => "|"
    @ast.Token::PipeAnd => "|&"
    @ast.Token::And => "&&"
    @ast.Token::Or => "||"
    @ast.Token::Ampersand => "&"
    @ast.Token::Bang => "!"
    @ast.Token::Semi => ";"
    @ast.Token::RedirectIn => "<"
    @ast.Token::RedirectOut => ">"
    @ast.Token::RedirectAppend => ">>"
    @ast.Token::HereDoc => "<<"
    @ast.Token::HereDocStrip => "<<-"
    @ast.Token::HereString => "<<<"
    @ast.Token::RedirectInOut => "<>"
    @ast.Token::RedirectClobber => ">|"
    @ast.Token::DupIn => "<&"
    @ast.Token::DupOut => ">&"
    @ast.Token::RedirectAndOut => "&>"
    @ast.Token::RedirectAndAppend => "&>>"
    @ast.Token::If => "if"
    @ast.Token::Then => "then"
    @ast.Token::Elif => "elif"
    @ast.Token::Else => "else"
    @ast.Token::Fi => "fi"
    @ast.Token::For => "for"
    @ast.Token::While => "while"
    @ast.Token::Until => "until"
    @ast.Token::Do => "do"
    @ast.Token::Done => "done"
    @ast.Token::Case => "case"
    @ast.Token::Esac => "esac"
    @ast.Token::In => "in"
    @ast.Token::Function => "function"
    @ast.Token::Select => "select"
    @ast.Token::Time => "time"
    @ast.Token::Newline => " "
    @ast.Token::LeftParen => "("
    @ast.Token::RightParen => ")"
    @ast.Token::LeftBrace => "{"
    @ast.Token::RightBrace => "}"
    @ast.Token::DoubleBracketOpen => "[["
    @ast.Token::DoubleBracketClose => "]]"
    @ast.Token::FdNumber(n) => n.to_string()
    @ast.Token::EOF => ""
  }
}

fn Parser::parse_arithmetic_raw(self : Parser) -> String raise @ast.BashError {
  let buf = StringBuilder::new()
  let mut depth = 0

  while not(self.at_end()) {
    let tok = self.advance()
    match tok {
      @ast.Token::LeftParen => {
        depth += 1
        buf.write_char('(')
      }
      @ast.Token::RightParen => {
        if depth > 0 {
          depth -= 1
          buf.write_char(')')
        } else if self.match_token(@ast.Token::RightParen) {
          return buf.to_string()
        } else {
          buf.write_char(')')
        }
      }
      _ => {
        let text = arith_token_to_string(tok)
        if text.length() == 0 {
          continue
        }
        buf.write_string(text)
      }
    }
  }

  raise @ast.BashError("unterminated arithmetic command")
}

// ============================================================================
// Script Parsing
// ============================================================================

/// Parse a complete script (sequence of statements).
fn Parser::parse_script(self : Parser) -> @ast.Script raise @ast.BashError {
  let statements : Array[@ast.Statement] = []
  self.skip_newlines()
  while not(self.at_end()) && not(self.is_script_terminator()) {
    let stmt = self.parse_statement()
    statements.push(stmt)
    // Consume statement separators (but not ;; which is a case terminator)
    while self.match_token(@ast.Token::Newline) {
      // skip newlines
    }
    // Only consume ; if it's not part of ;; (case terminator)
    while self.check(@ast.Token::Semi) && not(self.peek_at_offset(1) == @ast.Token::Semi) {
      self.advance() |> ignore
    }
  }
  { statements, }
}

/// Check if the current token terminates a script context (fi, done, esac, etc.)
fn Parser::is_script_terminator(self : Parser) -> Bool {
  match self.peek() {
    @ast.Token::Fi
    | @ast.Token::Done
    | @ast.Token::Esac
    | @ast.Token::Else
    | @ast.Token::Elif
    | @ast.Token::Then
    | @ast.Token::Do
    | @ast.Token::RightBrace
    | @ast.Token::RightParen => true
    @ast.Token::Semi => {
      // Check for ;; (case terminator): two consecutive Semi tokens
      self.peek_at_offset(1) == @ast.Token::Semi
    }
    _ => false
  }
}

fn Parser::peek_at_offset(self : Parser, offset : Int) -> @ast.Token {
  let idx = self.pos + offset
  if idx >= self.tokens.length() {
    @ast.Token::EOF
  } else {
    self.tokens[idx]
  }
}

// ============================================================================
// Statement Parsing
// ============================================================================

/// Parse a statement: pipeline (&&/|| pipeline)* [;/&]
fn Parser::parse_statement(self : Parser) -> @ast.Statement raise @ast.BashError {
  let pipeline = self.parse_pipeline()

  // Check for list operators
  match self.peek() {
    @ast.Token::And => {
      self.advance() |> ignore
      self.skip_newlines()
      let right = self.parse_statement()
      @ast.Statement::AndList(pipeline, right)
    }
    @ast.Token::Or => {
      self.advance() |> ignore
      self.skip_newlines()
      let right = self.parse_statement()
      @ast.Statement::OrList(pipeline, right)
    }
    @ast.Token::Ampersand => {
      self.advance() |> ignore
      @ast.Statement::Background(pipeline)
    }
    @ast.Token::Semi => {
      // Check for ;; (case terminator) - don't consume it
      if self.peek_at_offset(1) == @ast.Token::Semi {
        @ast.Statement::Pipeline(pipeline)
      } else {
        self.advance() |> ignore
        self.skip_newlines()
        if self.at_end() || self.is_script_terminator() {
          @ast.Statement::Pipeline(pipeline)
        } else {
          let right = self.parse_statement()
          @ast.Statement::Sequence(pipeline, right)
        }
      }
    }
    _ => @ast.Statement::Pipeline(pipeline)
  }
}

// ============================================================================
// Pipeline Parsing
// ============================================================================

/// Parse a pipeline: [!] command (| command)*
fn Parser::parse_pipeline(self : Parser) -> @ast.Pipeline raise @ast.BashError {
  let negated = self.match_token(@ast.Token::Bang)
  let commands : Array[@ast.Command] = []
  let mut pipe_stderr = false

  commands.push(self.parse_command())

  while true {
    match self.peek() {
      @ast.Token::Pipe => {
        self.advance() |> ignore
        self.skip_newlines()
        commands.push(self.parse_command())
      }
      @ast.Token::PipeAnd => {
        self.advance() |> ignore
        pipe_stderr = true
        self.skip_newlines()
        commands.push(self.parse_command())
      }
      _ => break
    }
  }

  { negated, commands, pipe_stderr }
}

// ============================================================================
// Command Parsing
// ============================================================================

/// Parse a command: simple, compound, or function definition.
fn Parser::parse_command(self : Parser) -> @ast.Command raise @ast.BashError {
  if self.is_double_bracket_start() {
    return @ast.Command::Simple(self.parse_double_bracket_simple_command())
  }

  match self.peek() {
    // Compound commands
    @ast.Token::If => {
      self.enter_depth()
      let cmd = self.parse_if()
      let redirs = self.parse_redirections()
      self.leave_depth()
      @ast.Command::Compound(@ast.CompoundCommand::If(cmd), redirs)
    }
    @ast.Token::For => {
      self.enter_depth()
      let cmd = self.parse_for()
      let redirs = self.parse_redirections()
      self.leave_depth()
      @ast.Command::Compound(cmd, redirs)
    }
    @ast.Token::While => {
      self.enter_depth()
      let cmd = self.parse_while()
      let redirs = self.parse_redirections()
      self.leave_depth()
      @ast.Command::Compound(@ast.CompoundCommand::While(cmd), redirs)
    }
    @ast.Token::Until => {
      self.enter_depth()
      let cmd = self.parse_until()
      let redirs = self.parse_redirections()
      self.leave_depth()
      @ast.Command::Compound(@ast.CompoundCommand::Until(cmd), redirs)
    }
    @ast.Token::Case => {
      self.enter_depth()
      let cmd = self.parse_case()
      let redirs = self.parse_redirections()
      self.leave_depth()
      @ast.Command::Compound(@ast.CompoundCommand::Case(cmd), redirs)
    }
    @ast.Token::LeftParen => {
      if self.peek_at_offset(1) == @ast.Token::LeftParen {
        self.enter_depth()
        self.advance() |> ignore
        self.advance() |> ignore
        let raw_expr = self.parse_arithmetic_raw()
        let redirs = self.parse_redirections()
        self.leave_depth()
        @ast.Command::Compound(
          @ast.CompoundCommand::ArithmeticCommand(@ast.ArithExpr::Raw(raw_expr)),
          redirs,
        )
      } else {
        self.enter_depth()
        self.advance() |> ignore
        self.skip_newlines()
        let script = self.parse_script()
        self.skip_newlines()
        self.expect(@ast.Token::RightParen)
        let redirs = self.parse_redirections()
        self.leave_depth()
        @ast.Command::Compound(@ast.CompoundCommand::Subshell(script), redirs)
      }
    }
    @ast.Token::LeftBrace => {
      self.enter_depth()
      self.advance() |> ignore
      self.skip_newlines()
      let script = self.parse_script()
      self.skip_newlines()
      self.expect(@ast.Token::RightBrace)
      let redirs = self.parse_redirections()
      self.leave_depth()
      @ast.Command::Compound(@ast.CompoundCommand::Group(script), redirs)
    }
    @ast.Token::Function => {
      self.parse_function_def()
    }
    _ => {
      // Simple command or POSIX function definition: name() { ... }
      if self.looks_like_posix_function_def() {
        self.enter_depth()
        let fndef = self.parse_posix_function_def()
        self.leave_depth()
        fndef
      } else {
        @ast.Command::Simple(self.parse_simple_command())
      }
    }
  }
}

fn Parser::is_double_bracket_start(self : Parser) -> Bool {
  match self.peek() {
    @ast.Token::Word(s) => s == "[["
    @ast.Token::DoubleBracketOpen => true
    _ => false
  }
}

fn Parser::parse_double_bracket_simple_command(
  self : Parser
) -> @ast.SimpleCommand raise @ast.BashError {
  let assignments : Array[@ast.Assignment] = []
  let words : Array[@ast.Word] = []
  let redirections : Array[@ast.Redirection] = []

  let opening = self.advance()
  let opening_text = match opening {
    @ast.Token::Word(s) => s
    @ast.Token::DoubleBracketOpen => "[["
    tok => raise @ast.BashError("expected [[, got \{tok}")
  }
  words.push(parse_word_content(opening_text))

  let mut closed = false
  while not(self.at_end()) {
    if self.is_redirection() {
      redirections.push(self.parse_redirection())
      continue
    }
    match self.peek() {
      @ast.Token::Newline | @ast.Token::EOF => break
      _ => ()
    }

    let tok = self.advance()
    let token_text = match tok {
      @ast.Token::DoubleBracketClose => "]]"
      _ => arith_token_to_string(tok)
    }
    if token_text.length() == 0 {
      raise @ast.BashError("unsupported token in [[ expression")
    }
    words.push(parse_word_content(token_text))
    if token_text == "]]" {
      closed = true
      break
    }
  }

  if not(closed) {
    raise @ast.BashError("expected ]] to close conditional expression")
  }

  while self.is_redirection() {
    redirections.push(self.parse_redirection())
  }

  { assignments, words, redirections }
}

// ============================================================================
// Simple Command Parsing
// ============================================================================

/// Parse a simple command: [assignments] [words] [redirections]
fn Parser::parse_simple_command(self : Parser) -> @ast.SimpleCommand raise @ast.BashError {
  let assignments : Array[@ast.Assignment] = []
  let words : Array[@ast.Word] = []
  let redirections : Array[@ast.Redirection] = []
  let start_pos = self.pos

  // Parse leading assignments
  while true {
    match self.peek() {
      @ast.Token::AssignmentWord(name, value, append) => {
        self.advance() |> ignore
        let word_value : @ast.Word? = if value.length() > 0 {
          Some(parse_word_content(value))
        } else {
          None
        }
        assignments.push({ name, value: word_value, append })
      }
      _ => break
    }
  }

  // Parse words and redirections
  while true {
    // Check for redirections
    if self.is_redirection() {
      redirections.push(self.parse_redirection())
      continue
    }

    if self.is_word() {
      let tok = self.advance()
      words.push(parse_word_content(token_to_string(tok)))
      continue
    }
    break
  }

  if self.pos == start_pos {
    raise @ast.BashError("expected command, got \{self.peek()}")
  }

  self.consume_heredoc_bodies(redirections)

  { assignments, words, redirections }
}

// ============================================================================
// Redirection Parsing
// ============================================================================

/// Check if current token starts a redirection.
fn Parser::is_redirection(self : Parser) -> Bool {
  match self.peek() {
    @ast.Token::RedirectIn
    | @ast.Token::RedirectOut
    | @ast.Token::RedirectAppend
    | @ast.Token::RedirectClobber
    | @ast.Token::HereDoc
    | @ast.Token::HereDocStrip
    | @ast.Token::HereString
    | @ast.Token::DupIn
    | @ast.Token::DupOut
    | @ast.Token::RedirectInOut
    | @ast.Token::RedirectAndOut
    | @ast.Token::RedirectAndAppend
    | @ast.Token::FdNumber(_) => true
    _ => false
  }
}

/// Parse redirections that follow a command.
fn Parser::parse_redirections(self : Parser) -> Array[@ast.Redirection] raise @ast.BashError {
  let redirs : Array[@ast.Redirection] = []
  while self.is_redirection() {
    redirs.push(self.parse_redirection())
  }
  redirs
}

/// Parse a single redirection.
fn Parser::parse_redirection(self : Parser) -> @ast.Redirection raise @ast.BashError {
  let mut fd : Int? = None

  // Check for fd number prefix
  match self.peek() {
    @ast.Token::FdNumber(n) => {
      self.advance() |> ignore
      fd = Some(n)
    }
    _ => ()
  }

  let op : @ast.RedirectOp = match self.advance() {
    @ast.Token::RedirectIn => @ast.RedirectOp::Input
    @ast.Token::RedirectOut => @ast.RedirectOp::Output
    @ast.Token::RedirectAppend => @ast.RedirectOp::Append
    @ast.Token::RedirectClobber => @ast.RedirectOp::Clobber
    @ast.Token::RedirectInOut => @ast.RedirectOp::InputOutput
    @ast.Token::HereDoc => @ast.RedirectOp::HereDoc(false)
    @ast.Token::HereDocStrip => @ast.RedirectOp::HereDoc(true)
    @ast.Token::HereString => @ast.RedirectOp::HereString
    @ast.Token::DupIn => @ast.RedirectOp::DupInput
    @ast.Token::DupOut => @ast.RedirectOp::DupOutput
    @ast.Token::RedirectAndOut => @ast.RedirectOp::AndOutput
    @ast.Token::RedirectAndAppend => @ast.RedirectOp::AndAppend
    tok => raise @ast.BashError("unexpected token in redirection: \{tok}")
  }

  // Parse the target word
  let target = match self.peek() {
    @ast.Token::Word(s) => {
      self.advance() |> ignore
      match op {
        @ast.RedirectOp::HereDoc(_strip_tabs) => {
          // Quoted heredoc delimiters disable body expansion.
          if has_single_quote_markers(s) {
            let quoted_word : @ast.Word = {
              parts: [@ast.WordPart::SingleQuoted(strip_single_quote_markers(s))]
            }
            quoted_word
          } else {
            parse_word_content(s)
          }
        }
        _ => parse_word_content(s)
      }
    }
    @ast.Token::Number(n) => {
      self.advance() |> ignore
      make_literal_word(n.to_string())
    }
    tok => raise @ast.BashError("expected word after redirection, got \{tok}")
  }

  { fd, fd_var: None, op, target }
}

fn Parser::consume_heredoc_bodies(
  self : Parser,
  redirections : Array[@ast.Redirection]
) -> Unit raise @ast.BashError {
  let mut heredoc_count = 0
  for redir in redirections {
    match redir.op {
      @ast.RedirectOp::HereDoc(_strip_tabs) => heredoc_count += 1
      _ => ()
    }
  }
  if heredoc_count == 0 {
    return
  }

  // Heredoc payload starts on the next physical line.
  if self.check(@ast.Token::Newline) {
    self.advance() |> ignore
  } else {
    return
  }

  for i = 0; i < redirections.length(); i = i + 1 {
    match redirections[i].op {
      @ast.RedirectOp::HereDoc(_strip_tabs) => {
        let (delimiter, quoted_delim) = heredoc_delimiter(redirections[i].target)
        let body = self.read_heredoc_until(delimiter)
        let body_word : @ast.Word = if quoted_delim {
          {
            parts: [@ast.WordPart::SingleQuoted(body)]
          }
        } else {
          parse_word_content(body)
        }
        let redir = redirections[i]
        redirections[i] = { fd: redir.fd, fd_var: redir.fd_var, op: redir.op, target: body_word }
      }
      _ => ()
    }
  }
}

fn Parser::read_heredoc_until(
  self : Parser,
  delimiter : String
) -> String raise @ast.BashError {
  let body = StringBuilder::new()
  while not(self.at_end()) {
    let line = self.read_line_tokens()
    if line == delimiter {
      return body.to_string()
    }
    body.write_string(line)
    body.write_char('\n')
  }
  raise @ast.BashError("unexpected EOF while looking for matching heredoc delimiter")
}

fn Parser::read_line_tokens(self : Parser) -> String {
  let parts : Array[String] = []
  while not(self.at_end()) && not(self.check(@ast.Token::Newline)) {
    let tok = self.advance()
    parts.push(token_line_text(tok))
  }
  if self.check(@ast.Token::Newline) {
    self.advance() |> ignore
  }
  join_tokens_with_space(parts)
}

fn token_line_text(tok : @ast.Token) -> String {
  match tok {
    @ast.Token::Word(s) => strip_single_quote_markers(s)
    @ast.Token::Number(n) => n.to_string()
    @ast.Token::Semi => ";"
    @ast.Token::Pipe => "|"
    @ast.Token::PipeAnd => "|&"
    @ast.Token::And => "&&"
    @ast.Token::Or => "||"
    @ast.Token::Ampersand => "&"
    @ast.Token::LeftParen => "("
    @ast.Token::RightParen => ")"
    @ast.Token::LeftBrace => "{"
    @ast.Token::RightBrace => "}"
    @ast.Token::Bang => "!"
    @ast.Token::If => "if"
    @ast.Token::Then => "then"
    @ast.Token::Elif => "elif"
    @ast.Token::Else => "else"
    @ast.Token::Fi => "fi"
    @ast.Token::For => "for"
    @ast.Token::While => "while"
    @ast.Token::Until => "until"
    @ast.Token::Do => "do"
    @ast.Token::Done => "done"
    @ast.Token::Case => "case"
    @ast.Token::Esac => "esac"
    @ast.Token::In => "in"
    @ast.Token::Function => "function"
    @ast.Token::Select => "select"
    @ast.Token::Time => "time"
    @ast.Token::RedirectIn => "<"
    @ast.Token::RedirectOut => ">"
    @ast.Token::RedirectAppend => ">>"
    @ast.Token::RedirectClobber => ">|"
    @ast.Token::HereDoc => "<<"
    @ast.Token::HereDocStrip => "<<-"
    @ast.Token::HereString => "<<<"
    @ast.Token::DupIn => "<&"
    @ast.Token::DupOut => ">&"
    @ast.Token::RedirectInOut => "<>"
    @ast.Token::RedirectAndOut => "&>"
    @ast.Token::RedirectAndAppend => "&>>"
    @ast.Token::AssignmentWord(name, value, append) => {
      if value.length() == 0 {
        if append { name + "+=" } else { name + "=" }
      } else {
        let rendered = strip_single_quote_markers(value)
        if append { name + "+=" + rendered } else { name + "=" + rendered }
      }
    }
    @ast.Token::FdNumber(n) => n.to_string()
    @ast.Token::DoubleBracketOpen => "[["
    @ast.Token::DoubleBracketClose => "]]"
    @ast.Token::Newline | @ast.Token::EOF => ""
  }
}

fn join_tokens_with_space(parts : Array[String]) -> String {
  let out = StringBuilder::new()
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      out.write_char(' ')
    }
    out.write_string(parts[i])
  }
  out.to_string()
}

fn heredoc_delimiter(word : @ast.Word) -> (String, Bool) {
  let out = StringBuilder::new()
  let mut quoted = false
  for part in word.parts {
    match part {
      @ast.WordPart::Literal(s) => out.write_string(s)
      @ast.WordPart::SingleQuoted(s) => {
        quoted = true
        out.write_string(s)
      }
      @ast.WordPart::DoubleQuoted(inner) => {
        quoted = true
        for p in inner {
          match p {
            @ast.WordPart::Literal(s) => out.write_string(s)
            @ast.WordPart::SingleQuoted(s) => out.write_string(s)
            _ => ()
          }
        }
      }
      _ => ()
    }
  }
  (out.to_string(), quoted)
}

fn has_single_quote_markers(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int().unsafe_to_char() == '\u0001' {
      return true
    }
  }
  false
}

fn strip_single_quote_markers(s : String) -> String {
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

// ============================================================================
// Function Definition
// ============================================================================

fn Parser::parse_function_def(self : Parser) -> @ast.Command raise @ast.BashError {
  self.expect(@ast.Token::Function)
  let name = match self.advance() {
    @ast.Token::Word(s) => s
    tok => raise @ast.BashError("expected function name, got \{tok}")
  }
  // Optional ()
  if self.match_token(@ast.Token::LeftParen) {
    self.expect(@ast.Token::RightParen)
  }
  self.skip_newlines()
  // Parse body (must be a compound command)
  let body = match self.parse_command() {
    @ast.Command::Compound(cmd, _) => cmd
    _ => raise @ast.BashError("function body must be a compound command")
  }
  let redirections = self.parse_redirections()
  @ast.Command::FunctionDef({ name, body, redirections })
}

fn Parser::looks_like_posix_function_def(self : Parser) -> Bool {
  match self.peek() {
    @ast.Token::Word(_) => {
      if self.peek_at_offset(1) != @ast.Token::LeftParen ||
        self.peek_at_offset(2) != @ast.Token::RightParen {
        return false
      }
      let mut i = 3
      while self.peek_at_offset(i) == @ast.Token::Newline {
        i += 1
      }
      match self.peek_at_offset(i) {
        @ast.Token::LeftBrace
        | @ast.Token::If
        | @ast.Token::For
        | @ast.Token::While
        | @ast.Token::Until
        | @ast.Token::Case
        | @ast.Token::LeftParen => true
        _ => false
      }
    }
    _ => false
  }
}

fn Parser::parse_posix_function_def(
  self : Parser
) -> @ast.Command raise @ast.BashError {
  let name = match self.advance() {
    @ast.Token::Word(s) => s
    tok => raise @ast.BashError("expected function name, got \{tok}")
  }
  self.expect(@ast.Token::LeftParen)
  self.expect(@ast.Token::RightParen)
  self.skip_newlines()
  let body = match self.parse_command() {
    @ast.Command::Compound(cmd, _) => cmd
    _ => raise @ast.BashError("function body must be a compound command")
  }
  let redirections = self.parse_redirections()
  @ast.Command::FunctionDef({ name, body, redirections })
}

// ============================================================================
// Word Construction Helpers
// ============================================================================

/// Create a word with a single literal part.
fn make_literal_word(s : String) -> @ast.Word {
  { parts: [@ast.WordPart::Literal(s)] }
}

/// Parse word content string into Word with parts (variable expansion, etc.).
pub fn parse_word_content(s : String) -> @ast.Word {
  let parts = parse_word_parts(s)
  { parts, }
}
