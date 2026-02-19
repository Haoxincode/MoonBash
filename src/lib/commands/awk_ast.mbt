// moon_bash Commands - awk statement AST parsing

priv enum AwkStmt {
  Simple(String)
  If(AwkExprAst, Array[AwkStmt], Array[AwkStmt]?)
  For(Array[AwkStmt], AwkExprAst?, Array[AwkStmt], Array[AwkStmt])
  ForIn(String, String, Array[AwkStmt])
  Next
  Exit(AwkExprAst?)
  Return(AwkExprAst?)
  Printf(String)
  Print(String)
  Delete(String)
  PipeGetline(AwkExprAst, String)
  Getline(String)
  ExprStmt(AwkExprAst)
} derive(Show)

fn awk_stmt_ast_supports_expr(stmt : String) -> Bool {
  let t = aj_trim(stmt)
  if t.length() == 0 {
    return false
  }

  if (aj_starts_with(t, "system(") || aj_starts_with(t, "gsub(") ||
    aj_starts_with(t, "sub(") || aj_starts_with(t, "match(")) &&
    aj_ends_with(t, ")") {
    return false
  }

  if awk_find_top_level_token(t, "+=") > 0 ||
    awk_find_top_level_token(t, "-=") > 0 ||
    awk_find_top_level_token(t, "*=") > 0 ||
    awk_find_top_level_token(t, "/=") > 0 {
    return false
  }

  let eq_idx = awk_find_top_level_token(t, "=")
  if eq_idx > 0 {
    let prev = t[eq_idx - 1].to_int().unsafe_to_char()
    let next = if eq_idx + 1 < t.length() {
      Some(t[eq_idx + 1].to_int().unsafe_to_char())
    } else {
      None
    }
    if prev != '!' && prev != '<' && prev != '>' && prev != '=' &&
      next != Some('=') {
      let lhs = aj_trim(aj_substr(t, 0, eq_idx))
      if aj_starts_with(lhs, "$") {
        return false
      }
    }
  }

  true
}

fn awk_parse_statement_ast(stmt : String) -> AwkStmt {
  let text = aj_trim(stmt)
  if text.length() == 0 {
    return Simple("")
  }

  if text == "next" {
    return Next
  }

  if text == "exit" || aj_starts_with(text, "exit ") || aj_starts_with(text, "exit(") {
    let expr_text = if text.length() > 4 {
      aj_trim(aj_substr(text, 4, text.length()))
    } else {
      ""
    }
    let expr_ast = if expr_text.length() > 0 { Some(awk_parse_expr_ast(expr_text)) } else { None }
    return Exit(expr_ast)
  }

  if text == "return" || aj_starts_with(text, "return ") || aj_starts_with(text, "return(") {
    let expr_text = if text.length() > 6 {
      aj_trim(aj_substr(text, 6, text.length()))
    } else {
      ""
    }
    let expr_ast = if expr_text.length() > 0 { Some(awk_parse_expr_ast(expr_text)) } else { None }
    return Return(expr_ast)
  }

  let pipe_getline_idx = awk_find_top_level_token(text, "| getline")
  if pipe_getline_idx > 0 {
    let cmd_expr = aj_trim(aj_substr(text, 0, pipe_getline_idx))
    let target = aj_trim(aj_substr(text, pipe_getline_idx + 9, text.length()))
    return PipeGetline(awk_parse_expr_ast(cmd_expr), target)
  }

  if text == "getline" || aj_starts_with(text, "getline ") {
    let tail = if text.length() > 7 { aj_trim(aj_substr(text, 7, text.length())) } else { "" }
    return Getline(tail)
  }

  if aj_starts_with(text, "delete ") {
    return Delete(aj_trim(aj_substr(text, 6, text.length())))
  }

  if aj_starts_with(text, "printf") {
    return Printf(aj_trim(aj_substr(text, 6, text.length())))
  }

  if aj_starts_with(text, "print") && not(aj_starts_with(text, "printf")) {
    return Print(aj_trim(aj_substr(text, 5, text.length())))
  }

  match awk_parse_for_in_statement(text) {
    Some((loop_var, arr_name, body_stmt)) => {
      let body_ast = awk_parse_action_ast(body_stmt)
      return ForIn(loop_var, arr_name, body_ast)
    }
    None => ()
  }

  match awk_parse_for_statement(text) {
    Some((init_stmt, cond_expr, update_stmt, body_stmt)) => {
      let init_ast = awk_parse_action_ast(init_stmt)
      let cond_ast = if aj_trim(cond_expr).length() == 0 {
        None
      } else {
        Some(awk_parse_expr_ast(cond_expr))
      }
      let update_ast = awk_parse_action_ast(update_stmt)
      let body_ast = awk_parse_action_ast(body_stmt)
      return For(init_ast, cond_ast, update_ast, body_ast)
    }
    None => ()
  }

  match awk_parse_if_statement(text) {
    Some((cond_expr, body_stmt)) => {
      let cond_ast = awk_parse_expr_ast(cond_expr)
      let (then_body, else_body) = awk_split_if_else_body(body_stmt)
      let then_ast = awk_parse_action_ast(then_body)
      match else_body {
        Some(else_stmt) => If(cond_ast, then_ast, Some(awk_parse_action_ast(else_stmt)))
        None => If(cond_ast, then_ast, None)
      }
    }
    None => {
      if awk_stmt_ast_supports_expr(text) {
        ExprStmt(awk_parse_expr_ast(text))
      } else {
        Simple(text)
      }
    }
  }
}

fn awk_parse_action_ast(action : String) -> Array[AwkStmt] {
  let merged = awk_merge_if_else_statements(awk_split_statements(action))
  let out : Array[AwkStmt] = []
  for stmt_raw in merged {
    let stmt = awk_parse_statement_ast(stmt_raw)
    match stmt {
      Simple(text) => {
        if aj_trim(text).length() > 0 {
          out.push(stmt)
        }
      }
      _ => out.push(stmt)
    }
  }
  out
}
