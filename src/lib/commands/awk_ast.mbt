// moon_bash Commands - awk statement AST parsing

priv enum AwkStmt {
  Simple(String)
  If(AwkExprAst, Array[AwkStmt], Array[AwkStmt]?)
  For(Array[AwkStmt], AwkExprAst?, Array[AwkStmt], Array[AwkStmt])
  ForIn(String, String, Array[AwkStmt])
} derive(Show)

fn awk_parse_statement_ast(stmt : String) -> AwkStmt {
  let text = aj_trim(stmt)
  if text.length() == 0 {
    return Simple("")
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
    None => Simple(text)
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
