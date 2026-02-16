// moon_bash Lexer Tests

// ============================================================================
// Simple Commands
// ============================================================================

test "tokenize simple command" {
  let tokens = tokenize("echo hello world")
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hello"))
  assert_eq(tokens[2], @ast.Token::Word("world"))
  assert_eq(tokens[3], @ast.Token::EOF)
}

test "tokenize empty input" {
  let tokens = tokenize("")
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0], @ast.Token::EOF)
}

test "tokenize whitespace only" {
  let tokens = tokenize("   \t  ")
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0], @ast.Token::EOF)
}

// ============================================================================
// Quoted Strings
// ============================================================================

test "tokenize single quoted string" {
  let tokens = tokenize("echo 'hello world'")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hello world"))
  assert_eq(tokens[2], @ast.Token::EOF)
}

test "tokenize double quoted string" {
  let tokens = tokenize("echo \"hello world\"")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hello world"))
  assert_eq(tokens[2], @ast.Token::EOF)
}

test "tokenize double quoted with dollar" {
  let tokens = tokenize("echo \"hello $USER\"")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hello $USER"))
  assert_eq(tokens[2], @ast.Token::EOF)
}

// ============================================================================
// Pipes
// ============================================================================

test "tokenize pipe" {
  let tokens = tokenize("cmd1 | cmd2")
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0], @ast.Token::Word("cmd1"))
  assert_eq(tokens[1], @ast.Token::Pipe)
  assert_eq(tokens[2], @ast.Token::Word("cmd2"))
  assert_eq(tokens[3], @ast.Token::EOF)
}

test "tokenize pipe-and" {
  let tokens = tokenize("cmd1 |& cmd2")
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0], @ast.Token::Word("cmd1"))
  assert_eq(tokens[1], @ast.Token::PipeAnd)
  assert_eq(tokens[2], @ast.Token::Word("cmd2"))
  assert_eq(tokens[3], @ast.Token::EOF)
}

// ============================================================================
// Redirections
// ============================================================================

test "tokenize redirect out" {
  let tokens = tokenize("echo hi > file")
  assert_eq(tokens.length(), 5)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hi"))
  assert_eq(tokens[2], @ast.Token::RedirectOut)
  assert_eq(tokens[3], @ast.Token::Word("file"))
  assert_eq(tokens[4], @ast.Token::EOF)
}

test "tokenize redirect append" {
  let tokens = tokenize("echo hi >> file")
  assert_eq(tokens[2], @ast.Token::RedirectAppend)
}

test "tokenize redirect in" {
  let tokens = tokenize("cmd < input")
  assert_eq(tokens[1], @ast.Token::RedirectIn)
}

test "tokenize heredoc" {
  let tokens = tokenize("cmd << EOF")
  assert_eq(tokens[1], @ast.Token::HereDoc)
}

test "tokenize herestring" {
  let tokens = tokenize("cmd <<< word")
  assert_eq(tokens[1], @ast.Token::HereString)
}

test "tokenize fd redirect" {
  let tokens = tokenize("cmd 2> file")
  assert_eq(tokens[1], @ast.Token::FdNumber(2))
  assert_eq(tokens[2], @ast.Token::RedirectOut)
}

test "tokenize redirect clobber" {
  let tokens = tokenize("cmd >| file")
  assert_eq(tokens[1], @ast.Token::RedirectClobber)
}

test "tokenize dup output" {
  let tokens = tokenize("cmd >& 2")
  assert_eq(tokens[1], @ast.Token::DupOut)
}

test "tokenize and-redirect" {
  let tokens = tokenize("cmd &> file")
  assert_eq(tokens[1], @ast.Token::RedirectAndOut)
}

test "tokenize and-redirect-append" {
  let tokens = tokenize("cmd &>> file")
  assert_eq(tokens[1], @ast.Token::RedirectAndAppend)
}

// ============================================================================
// Operators
// ============================================================================

test "tokenize and-list" {
  let tokens = tokenize("cmd1 && cmd2")
  assert_eq(tokens[1], @ast.Token::And)
}

test "tokenize or-list" {
  let tokens = tokenize("cmd1 || cmd2")
  assert_eq(tokens[1], @ast.Token::Or)
}

test "tokenize semicolon" {
  let tokens = tokenize("cmd1 ; cmd2")
  assert_eq(tokens[1], @ast.Token::Semi)
}

test "tokenize background" {
  let tokens = tokenize("cmd &")
  assert_eq(tokens[1], @ast.Token::Ampersand)
}

// ============================================================================
// Grouping
// ============================================================================

test "tokenize parens" {
  let tokens = tokenize("(cmd)")
  assert_eq(tokens[0], @ast.Token::LeftParen)
  assert_eq(tokens[1], @ast.Token::Word("cmd"))
  assert_eq(tokens[2], @ast.Token::RightParen)
}

test "tokenize braces" {
  let tokens = tokenize("{ cmd; }")
  assert_eq(tokens[0], @ast.Token::LeftBrace)
  assert_eq(tokens[1], @ast.Token::Word("cmd"))
  assert_eq(tokens[2], @ast.Token::Semi)
  assert_eq(tokens[3], @ast.Token::RightBrace)
}

// ============================================================================
// Assignment
// ============================================================================

test "tokenize assignment" {
  let tokens = tokenize("VAR=value")
  assert_eq(tokens[0], @ast.Token::AssignmentWord("VAR", "value"))
}

test "tokenize assignment empty value" {
  let tokens = tokenize("VAR=")
  assert_eq(tokens[0], @ast.Token::AssignmentWord("VAR", ""))
}

// ============================================================================
// Comments
// ============================================================================

test "tokenize with comment" {
  let tokens = tokenize("echo hi # comment")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hi"))
  assert_eq(tokens[2], @ast.Token::EOF)
}

test "tokenize only comment" {
  let tokens = tokenize("# just a comment")
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0], @ast.Token::EOF)
}

// ============================================================================
// Reserved Words
// ============================================================================

test "tokenize if-then-fi" {
  let tokens = tokenize("if true; then echo yes; fi")
  assert_eq(tokens[0], @ast.Token::If)
  assert_eq(tokens[1], @ast.Token::Word("true"))
  assert_eq(tokens[2], @ast.Token::Semi)
  assert_eq(tokens[3], @ast.Token::Then)
  assert_eq(tokens[4], @ast.Token::Word("echo"))
  assert_eq(tokens[5], @ast.Token::Word("yes"))
  assert_eq(tokens[6], @ast.Token::Semi)
  assert_eq(tokens[7], @ast.Token::Fi)
  assert_eq(tokens[8], @ast.Token::EOF)
}

test "tokenize for-in-do-done" {
  let tokens = tokenize("for x in a b; do echo; done")
  assert_eq(tokens[0], @ast.Token::For)
  assert_eq(tokens[1], @ast.Token::Word("x"))
  assert_eq(tokens[2], @ast.Token::In)
  assert_eq(tokens[3], @ast.Token::Word("a"))
  assert_eq(tokens[4], @ast.Token::Word("b"))
  assert_eq(tokens[5], @ast.Token::Semi)
  assert_eq(tokens[6], @ast.Token::Do)
  assert_eq(tokens[7], @ast.Token::Word("echo"))
  assert_eq(tokens[8], @ast.Token::Semi)
  assert_eq(tokens[9], @ast.Token::Done)
  assert_eq(tokens[10], @ast.Token::EOF)
}

test "tokenize while-do-done" {
  let tokens = tokenize("while true; do echo; done")
  assert_eq(tokens[0], @ast.Token::While)
}

test "tokenize case-in-esac" {
  let tokens = tokenize("case x in esac")
  assert_eq(tokens[0], @ast.Token::Case)
  assert_eq(tokens[2], @ast.Token::In)
  assert_eq(tokens[3], @ast.Token::Esac)
}

test "tokenize function" {
  let tokens = tokenize("function foo")
  assert_eq(tokens[0], @ast.Token::Function)
}

// ============================================================================
// Newlines
// ============================================================================

test "tokenize newlines" {
  let tokens = tokenize("cmd1\ncmd2")
  assert_eq(tokens[0], @ast.Token::Word("cmd1"))
  assert_eq(tokens[1], @ast.Token::Newline)
  assert_eq(tokens[2], @ast.Token::Word("cmd2"))
  assert_eq(tokens[3], @ast.Token::EOF)
}

// ============================================================================
// Escape Sequences
// ============================================================================

test "tokenize backslash escape" {
  let tokens = tokenize("echo hello\\ world")
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0], @ast.Token::Word("echo"))
  assert_eq(tokens[1], @ast.Token::Word("hello world"))
  assert_eq(tokens[2], @ast.Token::EOF)
}

// ============================================================================
// Error Cases
// ============================================================================

test "unterminated single quote" {
  let mut got_error = false
  try {
    tokenize("echo 'hello") |> ignore
  } catch {
    @ast.BashError(_) => got_error = true
  }
  assert_true(got_error)
}

test "unterminated double quote" {
  let mut got_error = false
  try {
    tokenize("echo \"hello") |> ignore
  } catch {
    @ast.BashError(_) => got_error = true
  }
  assert_true(got_error)
}
