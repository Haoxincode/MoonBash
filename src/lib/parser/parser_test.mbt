// MoonBash Parser Tests

// ============================================================================
// Simple Commands
// ============================================================================

test "parse simple command" {
  let script = parse("echo hello world")
  assert_eq(script.statements.length(), 1)
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      assert_eq(pipeline.commands.length(), 1)
      match pipeline.commands[0] {
        @ast.Command::Simple(cmd) => {
          assert_eq(cmd.words.length(), 3)
        }
        _ => fail("expected simple command")
      }
    }
    _ => fail("expected pipeline")
  }
}

test "parse empty input" {
  let script = parse("")
  assert_eq(script.statements.length(), 0)
}

// ============================================================================
// Pipelines
// ============================================================================

test "parse pipeline" {
  let script = parse("cmd1 | cmd2 | cmd3")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      assert_eq(pipeline.commands.length(), 3)
      assert_eq(pipeline.negated, false)
    }
    _ => fail("expected pipeline")
  }
}

test "parse negated pipeline" {
  let script = parse("! cmd1 | cmd2")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      assert_true(pipeline.negated)
      assert_eq(pipeline.commands.length(), 2)
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// And/Or Lists
// ============================================================================

test "parse and-list" {
  let script = parse("cmd1 && cmd2")
  match script.statements[0] {
    @ast.Statement::AndList(_, _) => ()
    _ => fail("expected and-list")
  }
}

test "parse or-list" {
  let script = parse("cmd1 || cmd2")
  match script.statements[0] {
    @ast.Statement::OrList(_, _) => ()
    _ => fail("expected or-list")
  }
}

test "parse background" {
  let script = parse("cmd &")
  match script.statements[0] {
    @ast.Statement::Background(_) => ()
    _ => fail("expected background")
  }
}

test "parse sequence" {
  let script = parse("cmd1; cmd2")
  match script.statements[0] {
    @ast.Statement::Sequence(_, _) => ()
    _ => fail("expected sequence")
  }
}

// ============================================================================
// Redirections
// ============================================================================

test "parse redirect out" {
  let script = parse("echo hi > file")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Simple(cmd) => {
          assert_eq(cmd.redirections.length(), 1)
          assert_eq(cmd.redirections[0].op, @ast.RedirectOp::Output)
        }
        _ => fail("expected simple command")
      }
    }
    _ => fail("expected pipeline")
  }
}

test "parse fd redirect" {
  let script = parse("cmd 2> file")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Simple(cmd) => {
          assert_eq(cmd.redirections.length(), 1)
          assert_eq(cmd.redirections[0].fd, Some(2))
          assert_eq(cmd.redirections[0].op, @ast.RedirectOp::Output)
        }
        _ => fail("expected simple command")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// If Statement
// ============================================================================

test "parse if statement" {
  let script = parse("if true; then echo yes; fi")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::If(clause), _) => {
          assert_eq(clause.condition.statements.length(), 1)
          assert_eq(clause.then_branch.statements.length(), 1)
          assert_true(clause.else_branch is None)
        }
        _ => fail("expected if compound command")
      }
    }
    _ => fail("expected pipeline")
  }
}

test "parse if-else statement" {
  let script = parse("if true; then echo yes; else echo no; fi")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::If(clause), _) => {
          assert_true(not(clause.else_branch is None))
        }
        _ => fail("expected if compound command")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// For Statement
// ============================================================================

test "parse for statement" {
  let script = parse("for x in a b c; do echo; done")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::For(clause), _) => {
          assert_eq(clause.var_name, "x")
          match clause.words {
            Some(words) => assert_eq(words.length(), 3)
            None => fail("expected words list")
          }
        }
        _ => fail("expected for compound command")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// While Statement
// ============================================================================

test "parse while statement" {
  let script = parse("while true; do echo; done")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::While(_), _) => ()
        _ => fail("expected while compound command")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// Case Statement
// ============================================================================

test "parse case statement" {
  let script = parse("case x in a) echo a;; b) echo b;; esac")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::Case(clause), _) => {
          assert_eq(clause.items.length(), 2)
        }
        _ => fail("expected case compound command")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// Subshell and Group
// ============================================================================

test "parse subshell" {
  let script = parse("(echo hello)")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::Subshell(_), _) => ()
        _ => fail("expected subshell")
      }
    }
    _ => fail("expected pipeline")
  }
}

test "parse group" {
  let script = parse("{ echo hello; }")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Compound(@ast.CompoundCommand::Group(_), _) => ()
        _ => fail("expected group")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// Function Definition
// ============================================================================

test "parse function definition" {
  let script = parse("function foo { echo hi; }")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::FunctionDef(fdef) => {
          assert_eq(fdef.name, "foo")
        }
        _ => fail("expected function def")
      }
    }
    _ => fail("expected pipeline")
  }
}

// ============================================================================
// Word Expansion Parsing
// ============================================================================

test "parse word with variable" {
  let word = parse_word_content("hello$USER")
  assert_eq(word.parts.length(), 2)
  match word.parts[0] {
    @ast.WordPart::Literal(s) => assert_eq(s, "hello")
    _ => fail("expected literal")
  }
  match word.parts[1] {
    @ast.WordPart::Variable(s) => assert_eq(s, "USER")
    _ => fail("expected variable")
  }
}

test "parse word with brace expansion" {
  let word = parse_word_content("${VAR:-default}")
  assert_eq(word.parts.length(), 1)
  match word.parts[0] {
    @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Default(name, _, colon)) => {
      assert_eq(name, "VAR")
      assert_true(colon)
    }
    _ => fail("expected default expansion")
  }
}

test "parse word with command substitution" {
  let word = parse_word_content("$(echo hi)")
  assert_eq(word.parts.length(), 1)
  match word.parts[0] {
    @ast.WordPart::CommandSubstitution(s) => assert_eq(s, "echo hi")
    _ => fail("expected command substitution")
  }
}

test "parse word with length expansion" {
  let word = parse_word_content("${#VAR}")
  match word.parts[0] {
    @ast.WordPart::ParameterExpansion(@ast.ParamExpansion::Length(name)) =>
      assert_eq(name, "VAR")
    _ => fail("expected length expansion")
  }
}

test "parse word with tilde" {
  let word = parse_word_content("~/path")
  match word.parts[0] {
    @ast.WordPart::TildePrefix(s) => assert_eq(s, "")
    _ => fail("expected tilde prefix")
  }
}

test "parse word plain literal" {
  let word = parse_word_content("hello")
  assert_eq(word.parts.length(), 1)
  match word.parts[0] {
    @ast.WordPart::Literal(s) => assert_eq(s, "hello")
    _ => fail("expected literal")
  }
}

// ============================================================================
// Assignment
// ============================================================================

test "parse assignment" {
  let script = parse("VAR=value echo")
  match script.statements[0] {
    @ast.Statement::Pipeline(pipeline) => {
      match pipeline.commands[0] {
        @ast.Command::Simple(cmd) => {
          assert_eq(cmd.assignments.length(), 1)
          assert_eq(cmd.assignments[0].name, "VAR")
          assert_eq(cmd.words.length(), 1)
        }
        _ => fail("expected simple command")
      }
    }
    _ => fail("expected pipeline")
  }
}
