// MoonBash Interpreter - Control Flow
// Handles if/for/while/until/case/subshell/group compound commands.

// ============================================================================
// Compound Command Dispatch
// ============================================================================

fn ExecContext::execute_compound(
  self : ExecContext,
  cmd : @ast.CompoundCommand
) -> Unit {
  match cmd {
    @ast.CompoundCommand::If(clause) => self.execute_if(clause)
    @ast.CompoundCommand::For(clause) => self.execute_for(clause)
    @ast.CompoundCommand::While(clause) => self.execute_while(clause)
    @ast.CompoundCommand::Until(clause) => self.execute_until(clause)
    @ast.CompoundCommand::Case(clause) => self.execute_case(clause)
    @ast.CompoundCommand::Subshell(script) => self.execute_subshell(script)
    @ast.CompoundCommand::Group(script) => self.execute_script(script)
    @ast.CompoundCommand::CStyleFor(clause) => self.execute_cstyle_for(clause)
    @ast.CompoundCommand::ArithmeticCommand(expr) => {
      let result = self.eval_arith(expr)
      self.exit_code = if result != 0 { 0 } else { 1 }
    }
    @ast.CompoundCommand::ConditionalCommand(cond) =>
      self.execute_conditional(cond)
  }
}

// ============================================================================
// If Statement
// ============================================================================

fn ExecContext::execute_if(self : ExecContext, clause : @ast.IfClause) -> Unit {
  // Evaluate condition
  self.execute_script(clause.condition)
  if self.exit_code == 0 {
    self.execute_script(clause.then_branch)
    return
  }

  // Check elif branches
  for elif in clause.elif_branches {
    let (cond, body) = elif
    self.execute_script(cond)
    if self.exit_code == 0 {
      self.execute_script(body)
      return
    }
  }

  // Execute else branch if present
  match clause.else_branch {
    Some(else_body) => self.execute_script(else_body)
    None => self.exit_code = 0
  }
}

// ============================================================================
// For Loop
// ============================================================================

fn ExecContext::execute_for(self : ExecContext, clause : @ast.ForClause) -> Unit {
  let words = match clause.words {
    Some(word_list) => {
      let expanded : Array[String] = []
      for word in word_list {
        let parts = self.expand_word(word)
        for part in parts {
          expanded.push(part)
        }
      }
      expanded
    }
    None => {
      // Default to positional parameters ($@)
      let args_str = self.env.get("@").unwrap_or("")
      if args_str.length() > 0 {
        split_by_whitespace(args_str)
      } else {
        []
      }
    }
  }

  self.loop_depth += 1
  let mut iter_count = 0

  for word in words {
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }

    iter_count += 1
    if iter_count > self.limits.max_loop_iterations {
      self.fail_execution_limit("for loop: too many iterations")
      break
    }

    self.env[clause.var_name] = word
    self.execute_script(clause.body)
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }
    if self.continue_count > 0 {
      self.continue_count -= 1
      if self.continue_count > 0 {
        break
      }
      continue
    }
  }

  self.loop_depth -= 1
}

// ============================================================================
// While Loop
// ============================================================================

fn ExecContext::execute_while(
  self : ExecContext,
  clause : @ast.WhileClause
) -> Unit {
  self.loop_depth += 1
  let mut iter_count = 0
  let mut has_body_run = false
  let mut last_body_status = 0

  while true {
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }

    // Evaluate condition
    self.execute_script(clause.condition)
    if self.exit_code != 0 {
      self.exit_code = if has_body_run { last_body_status } else { 0 }
      break
    }

    iter_count += 1
    if iter_count > self.limits.max_loop_iterations {
      self.fail_execution_limit("while loop: too many iterations")
      break
    }

    // Execute body
    self.execute_script(clause.body)
    has_body_run = true
    last_body_status = self.exit_code
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }
    if self.continue_count > 0 {
      self.continue_count -= 1
      if self.continue_count > 0 {
        break
      }
      continue
    }
  }

  self.loop_depth -= 1
}

// ============================================================================
// Until Loop
// ============================================================================

fn ExecContext::execute_until(
  self : ExecContext,
  clause : @ast.UntilClause
) -> Unit {
  self.loop_depth += 1
  let mut iter_count = 0
  let mut has_body_run = false
  let mut last_body_status = 0

  while true {
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }

    // Evaluate condition
    self.execute_script(clause.condition)
    if self.exit_code == 0 {
      self.exit_code = if has_body_run { last_body_status } else { 0 }
      break
    }

    iter_count += 1
    if iter_count > self.limits.max_loop_iterations {
      self.fail_execution_limit("until loop: too many iterations")
      break
    }

    // Execute body
    self.execute_script(clause.body)
    has_body_run = true
    last_body_status = self.exit_code
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }
    if self.continue_count > 0 {
      self.continue_count -= 1
      if self.continue_count > 0 {
        break
      }
      continue
    }
  }

  self.loop_depth -= 1
}

// ============================================================================
// Case Statement
// ============================================================================

fn ExecContext::execute_case(self : ExecContext, clause : @ast.CaseClause) -> Unit {
  let word = self.expand_word_to_string(clause.word)

  for item in clause.items {
    let mut matched = false
    for pattern in item.patterns {
      let pat = self.expand_word_to_string(pattern)
      if simple_pattern_match(word, pat) {
        matched = true
        break
      }
    }
    if matched {
      self.execute_script(item.body)
      match item.terminator {
        @ast.CaseTerminator::Break => return
        @ast.CaseTerminator::Fallthrough => continue
        @ast.CaseTerminator::Continue => {
          // ;;&  - test next pattern
          continue
        }
      }
    }
  }
  self.exit_code = 0
}

// ============================================================================
// Subshell
// ============================================================================

fn ExecContext::execute_subshell(
  self : ExecContext,
  script : @ast.Script
) -> Unit {
  // Save environment - subshell modifications are discarded
  let saved_env : Map[String, String] = {}
  for k, v in self.env {
    saved_env[k] = v
  }
  let saved_cwd = self.cwd

  self.execute_script(script)

  // Restore environment (exit code persists)
  self.env = saved_env
  self.cwd = saved_cwd
}

// ============================================================================
// C-style For Loop
// ============================================================================

fn ExecContext::execute_cstyle_for(
  self : ExecContext,
  clause : @ast.CStyleForClause
) -> Unit {
  self.loop_depth += 1
  let mut iter_count = 0

  // Initialize
  self.eval_arith(clause.init) |> ignore

  while true {
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }

    iter_count += 1
    if iter_count > self.limits.max_loop_iterations {
      self.fail_execution_limit("for loop: too many iterations")
      break
    }

    // Check condition
    let cond = if cstyle_condition_omitted(clause.condition) {
      1
    } else {
      self.eval_arith(clause.condition)
    }
    if cond == 0 {
      break
    }

    // Execute body
    self.execute_script(clause.body)
    if self.should_exit || self.return_requested {
      break
    }
    if self.break_count > 0 {
      self.break_count -= 1
      break
    }
    let mut continue_requested = false
    if self.continue_count > 0 {
      self.continue_count -= 1
      if self.continue_count > 0 {
        break
      }
      continue_requested = true
    }

    // Update
    self.eval_arith(clause.update) |> ignore
    if continue_requested {
      continue
    }
  }

  self.loop_depth -= 1
}

// ============================================================================
// Conditional Command ([[ ]])
// ============================================================================

fn ExecContext::execute_conditional(
  self : ExecContext,
  cond : @ast.CondExpr
) -> Unit {
  let result = self.eval_cond(cond)
  self.exit_code = if result { 0 } else { 1 }
}

fn ExecContext::eval_cond(self : ExecContext, cond : @ast.CondExpr) -> Bool {
  match cond {
    @ast.CondExpr::UnaryTest(op, word) => {
      let value = self.expand_word_to_string(word)
      match op {
        "-z" => value.length() == 0
        "-n" => value.length() > 0
        "-f" => {
          let path = try {
            @fs.resolve_path(self.cwd, value)
          } catch {
            _ => return false
          }
          match self.fs.entries.get(path) {
            Some(@fs.FsEntry::File(_)) => true
            _ => false
          }
        }
        "-d" => {
          let path = try {
            @fs.resolve_path(self.cwd, value)
          } catch {
            _ => return false
          }
          match self.fs.entries.get(path) {
            Some(@fs.FsEntry::Directory(_)) => true
            _ => false
          }
        }
        "-e" => {
          let path = try {
            @fs.resolve_path(self.cwd, value)
          } catch {
            _ => return false
          }
          self.fs.exists(path)
        }
        "-s" => {
          let path = try {
            @fs.resolve_path(self.cwd, value)
          } catch {
            _ => return false
          }
          match self.fs.entries.get(path) {
            Some(@fs.FsEntry::File(data)) => data.content.length() > 0
            _ => false
          }
        }
        "-r" | "-w" | "-x" => {
          let path = try {
            @fs.resolve_path(self.cwd, value)
          } catch {
            _ => return false
          }
          self.fs.exists(path)
        }
        _ => false
      }
    }
    @ast.CondExpr::BinaryTest(left_word, op, right_word) => {
      let left = self.expand_word_to_string(left_word)
      let right = self.expand_word_to_string(right_word)
      match op {
        "=" | "==" => left == right
        "!=" => left != right
        "-eq" => parse_int_str(left) == parse_int_str(right)
        "-ne" => parse_int_str(left) != parse_int_str(right)
        "-lt" => parse_int_str(left) < parse_int_str(right)
        "-le" => parse_int_str(left) <= parse_int_str(right)
        "-gt" => parse_int_str(left) > parse_int_str(right)
        "-ge" => parse_int_str(left) >= parse_int_str(right)
        _ => false
      }
    }
    @ast.CondExpr::And(left, right) =>
      self.eval_cond(left) && self.eval_cond(right)
    @ast.CondExpr::Or(left, right) =>
      self.eval_cond(left) || self.eval_cond(right)
    @ast.CondExpr::Not(inner) => not(self.eval_cond(inner))
    @ast.CondExpr::Regex(left_word, right_word) => {
      let left = self.expand_word_to_string(left_word)
      let right = self.expand_word_to_string(right_word)
      regex_cond_match(left, right)
    }
  }
}

fn regex_cond_match(text : String, pattern : String) -> Bool {
  let matcher = try {
    @regex.compile_grep_matcher(
      pattern,
      extended=true,
      fixed=false,
      ignore_case=false,
    )
  } catch {
    _ => return false
  }
  matcher.find_first(text) is Some(_)
}

fn cstyle_condition_omitted(expr : @ast.ArithExpr) -> Bool {
  match expr {
    @ast.ArithExpr::Raw(raw) => trim_cstyle_expr(raw).length() == 0
    _ => false
  }
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
