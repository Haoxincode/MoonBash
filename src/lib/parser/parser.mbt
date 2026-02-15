// MoonBash Parser
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
  parser.parse_script()
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
    @ast.Token::AssignmentWord(_, _) => true
    _ => false
  }
}

/// Get the string value of the current token if it's word-like.
fn token_to_string(tok : @ast.Token) -> String {
  match tok {
    @ast.Token::Word(s) => s
    @ast.Token::Number(n) => n.to_string()
    _ => ""
  }
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
      @ast.Command::Compound(@ast.CompoundCommand::For(cmd), redirs)
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
      // Simple command (may also be a function definition: name() { ... })
      @ast.Command::Simple(self.parse_simple_command())
    }
  }
}

// ============================================================================
// Simple Command Parsing
// ============================================================================

/// Parse a simple command: [assignments] [words] [redirections]
fn Parser::parse_simple_command(self : Parser) -> @ast.SimpleCommand raise @ast.BashError {
  let assignments : Array[@ast.Assignment] = []
  let words : Array[@ast.Word] = []
  let redirections : Array[@ast.Redirection] = []

  // Parse leading assignments
  while true {
    match self.peek() {
      @ast.Token::AssignmentWord(name, value) => {
        self.advance() |> ignore
        let word_value : @ast.Word? = if value.length() > 0 {
          Some(make_literal_word(value))
        } else {
          None
        }
        assignments.push({ name, value: word_value, append: false })
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

    match self.peek() {
      @ast.Token::Word(s) => {
        self.advance() |> ignore
        words.push(parse_word_content(s))
      }
      @ast.Token::Number(n) => {
        self.advance() |> ignore
        words.push(make_literal_word(n.to_string()))
      }
      _ => break
    }
  }

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
      parse_word_content(s)
    }
    @ast.Token::Number(n) => {
      self.advance() |> ignore
      make_literal_word(n.to_string())
    }
    tok => raise @ast.BashError("expected word after redirection, got \{tok}")
  }

  { fd, fd_var: None, op, target }
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
