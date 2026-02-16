// moon_bash Parser - Compound Command Parsing
// Handles if, for, while, until, case statements.

// ============================================================================
// If Statement
// ============================================================================

/// Parse: if condition; then body [elif cond; then body]* [else body] fi
fn Parser::parse_if(self : Parser) -> @ast.IfClause raise @ast.BashError {
  self.expect(@ast.Token::If)
  self.skip_newlines()
  let condition = self.parse_script()
  self.skip_newlines()
  self.expect(@ast.Token::Then)
  self.skip_newlines()
  let then_branch = self.parse_script()

  let elif_branches : Array[(@ast.Script, @ast.Script)] = []
  let mut else_branch : @ast.Script? = None

  while self.match_token(@ast.Token::Elif) {
    self.skip_newlines()
    let elif_cond = self.parse_script()
    self.skip_newlines()
    self.expect(@ast.Token::Then)
    self.skip_newlines()
    let elif_body = self.parse_script()
    elif_branches.push((elif_cond, elif_body))
  }

  if self.match_token(@ast.Token::Else) {
    self.skip_newlines()
    else_branch = Some(self.parse_script())
  }

  self.skip_newlines()
  self.expect(@ast.Token::Fi)
  { condition, then_branch, elif_branches, else_branch }
}

// ============================================================================
// For Statement
// ============================================================================

/// Parse: for var [in words]; do body; done
///   or: for (( init; cond; update )); do body; done
fn Parser::parse_for(self : Parser) -> @ast.CompoundCommand raise @ast.BashError {
  self.expect(@ast.Token::For)

  if self.check(@ast.Token::LeftParen) &&
    self.peek_at_offset(1) == @ast.Token::LeftParen {
    self.advance() |> ignore
    self.advance() |> ignore
    let raw = self.parse_arithmetic_raw()
    let pieces = split_cstyle_for_expressions(raw)
    if pieces.length() != 3 {
      raise @ast.BashError("invalid C-style for expression")
    }

    while self.match_token(@ast.Token::Semi) || self.match_token(@ast.Token::Newline) {
      // skip separators
    }
    self.expect(@ast.Token::Do)
    self.skip_newlines()
    let body = self.parse_script()
    self.skip_newlines()
    self.expect(@ast.Token::Done)

    return @ast.CompoundCommand::CStyleFor({
      init: @ast.ArithExpr::Raw(pieces[0]),
      condition: @ast.ArithExpr::Raw(pieces[1]),
      update: @ast.ArithExpr::Raw(pieces[2]),
      body,
    })
  }

  let var_name = match self.advance() {
    @ast.Token::Word(s) => s
    tok => raise @ast.BashError("expected variable name after 'for', got \{tok}")
  }

  let mut words : Array[@ast.Word]? = None

  // Check for optional 'in words' or ';' or newline
  self.skip_newlines()
  if self.match_token(@ast.Token::In) {
    let word_list : Array[@ast.Word] = []
    while true {
      match self.peek() {
        @ast.Token::Word(s) => {
          self.advance() |> ignore
          word_list.push(parse_word_content(s))
        }
        @ast.Token::Number(n) => {
          self.advance() |> ignore
          word_list.push(make_literal_word(n.to_string()))
        }
        _ => break
      }
    }
    words = Some(word_list)
  }

  // Consume separator
  while self.match_token(@ast.Token::Semi) || self.match_token(@ast.Token::Newline) {
    // skip
  }

  self.expect(@ast.Token::Do)
  self.skip_newlines()
  let body = self.parse_script()
  self.skip_newlines()
  self.expect(@ast.Token::Done)
  @ast.CompoundCommand::For({ var_name, words, body })
}

fn split_cstyle_for_expressions(raw : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut paren_depth = 0

  for i = 0; i < raw.length(); i = i + 1 {
    let ch = raw[i].to_int().unsafe_to_char()
    if ch == '(' {
      paren_depth += 1
      buf.write_char(ch)
      continue
    }
    if ch == ')' {
      if paren_depth > 0 {
        paren_depth -= 1
      }
      buf.write_char(ch)
      continue
    }
    if ch == ';' && paren_depth == 0 {
      parts.push(trim_cstyle_expr(buf.to_string()))
      buf.reset()
      continue
    }
    buf.write_char(ch)
  }
  parts.push(trim_cstyle_expr(buf.to_string()))
  parts
}

fn trim_cstyle_expr(s : String) -> String {
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

// ============================================================================
// While Statement
// ============================================================================

/// Parse: while condition; do body; done
fn Parser::parse_while(self : Parser) -> @ast.WhileClause raise @ast.BashError {
  self.expect(@ast.Token::While)
  self.skip_newlines()
  let condition = self.parse_script()
  self.skip_newlines()
  self.expect(@ast.Token::Do)
  self.skip_newlines()
  let body = self.parse_script()
  self.skip_newlines()
  self.expect(@ast.Token::Done)
  { condition, body }
}

// ============================================================================
// Until Statement
// ============================================================================

/// Parse: until condition; do body; done
fn Parser::parse_until(self : Parser) -> @ast.UntilClause raise @ast.BashError {
  self.expect(@ast.Token::Until)
  self.skip_newlines()
  let condition = self.parse_script()
  self.skip_newlines()
  self.expect(@ast.Token::Do)
  self.skip_newlines()
  let body = self.parse_script()
  self.skip_newlines()
  self.expect(@ast.Token::Done)
  { condition, body }
}

// ============================================================================
// Case Statement
// ============================================================================

/// Parse: case word in [pattern) body ;;]* esac
fn Parser::parse_case(self : Parser) -> @ast.CaseClause raise @ast.BashError {
  self.expect(@ast.Token::Case)
  let word = match self.peek() {
    @ast.Token::Word(s) => {
      self.advance() |> ignore
      parse_word_content(s)
    }
    tok => raise @ast.BashError("expected word after 'case', got \{tok}")
  }
  self.skip_newlines()
  self.expect(@ast.Token::In)
  self.skip_newlines()

  let items : Array[@ast.CaseItem] = []

  while not(self.check(@ast.Token::Esac)) && not(self.at_end()) {
    // Parse optional (
    let _ = self.match_token(@ast.Token::LeftParen)

    // Parse patterns separated by |
    let patterns : Array[@ast.Word] = []
    while true {
      match self.peek() {
        @ast.Token::Word(s) => {
          self.advance() |> ignore
          patterns.push(parse_word_content(s))
        }
        @ast.Token::Number(n) => {
          self.advance() |> ignore
          patterns.push(make_literal_word(n.to_string()))
        }
        tok => raise @ast.BashError("expected pattern in case item, got \{tok}")
      }
      if self.match_token(@ast.Token::Pipe) {
        continue
      }
      break
    }

    self.expect(@ast.Token::RightParen)
    self.skip_newlines()

    // Parse body
    let body = self.parse_script()
    self.skip_newlines()

    // Parse terminator: ;; or ;& or ;;&
    let terminator = if self.check(@ast.Token::Semi) {
      self.advance() |> ignore
      if self.check(@ast.Token::Semi) {
        self.advance() |> ignore
        @ast.CaseTerminator::Break
      } else if self.check(@ast.Token::Ampersand) {
        self.advance() |> ignore
        @ast.CaseTerminator::Fallthrough
      } else {
        @ast.CaseTerminator::Break
      }
    } else {
      @ast.CaseTerminator::Break
    }

    items.push({ patterns, body, terminator })
    self.skip_newlines()
  }

  self.expect(@ast.Token::Esac)
  { word, items }
}
