// moon_bash Commands - awk statement AST parsing

priv enum AwkGetlineTarget {
  Record
  Var(String)
  Field(AwkExprAst)
  ArrayElem(String, AwkExprAst)
  Invalid(String)
} derive(Show)

priv enum AwkAssignTarget {
  Var(String)
  ArrayElem(String, AwkExprAst)
} derive(Show)

fn awk_parse_getline_target(target : String) -> AwkGetlineTarget {
  let t = aj_trim(target)
  if t.length() == 0 {
    Record
  } else if awk_is_identifier(t) {
    Var(t)
  } else if aj_starts_with(t, "$") && t.length() > 1 {
    Field(awk_parse_expr_ast(aj_substr(t, 1, t.length())))
  } else {
    match awk_parse_array_ref(t) {
      Some((arr_name, idx_expr)) => ArrayElem(arr_name, awk_parse_expr_ast(idx_expr))
      None => Invalid(t)
    }
  }
}

priv enum AwkStmt {
  If(AwkExprAst, Array[AwkStmt], Array[AwkStmt]?)
  For(Array[AwkStmt], AwkExprAst?, Array[AwkStmt], Array[AwkStmt])
  ForIn(String, String, Array[AwkStmt])
  While(AwkExprAst, Array[AwkStmt])
  Next
  Exit(AwkExprAst?)
  Return(AwkExprAst?)
  Printf(AwkExprAst, Array[AwkExprAst], AwkExprAst?, Bool)
  Print(Array[AwkExprAst], AwkExprAst?, Bool, Bool)
  Delete(String, AwkExprAst?)
  PipeGetline(AwkExprAst, AwkGetlineTarget)
  Getline(AwkGetlineTarget, AwkExprAst?)
  SystemStmt
  SubstituteStmt(Bool, Array[AwkExprAst])
  FieldAssignStmt(String, AwkExprAst)
  AssignStmt(AwkAssignTarget, AwkExprAst)
  CompoundAssignStmt(AwkAssignTarget, String, AwkExprAst)
  ExprStmt(AwkExprAst)
} derive(Show)

fn awk_parse_assign_target(lhs : String) -> AwkAssignTarget? {
  let t = aj_trim(lhs)
  if t.length() == 0 || aj_starts_with(t, "$") {
    return None
  }
  if awk_is_identifier(t) {
    return Some(Var(t))
  }
  match awk_parse_array_ref(t) {
    Some((arr_name, idx_expr)) => Some(ArrayElem(arr_name, awk_parse_expr_ast(idx_expr)))
    None => None
  }
}

fn awk_parse_compound_assign_stmt(text : String) -> (AwkAssignTarget, String, AwkExprAst)? {
  let plus_eq_idx = awk_find_top_level_token(text, "+=")
  if plus_eq_idx > 0 {
    let lhs = aj_substr(text, 0, plus_eq_idx)
    match awk_parse_assign_target(lhs) {
      Some(lhs_target) => {
        let rhs = aj_trim(aj_substr(text, plus_eq_idx + 2, text.length()))
        return Some((lhs_target, "+=", awk_parse_expr_ast(rhs)))
      }
      None => ()
    }
  }

  let minus_eq_idx = awk_find_top_level_token(text, "-=")
  if minus_eq_idx > 0 {
    let lhs = aj_substr(text, 0, minus_eq_idx)
    match awk_parse_assign_target(lhs) {
      Some(lhs_target) => {
        let rhs = aj_trim(aj_substr(text, minus_eq_idx + 2, text.length()))
        return Some((lhs_target, "-=", awk_parse_expr_ast(rhs)))
      }
      None => ()
    }
  }

  let mul_eq_idx = awk_find_top_level_token(text, "*=")
  if mul_eq_idx > 0 {
    let lhs = aj_substr(text, 0, mul_eq_idx)
    match awk_parse_assign_target(lhs) {
      Some(lhs_target) => {
        let rhs = aj_trim(aj_substr(text, mul_eq_idx + 2, text.length()))
        return Some((lhs_target, "*=", awk_parse_expr_ast(rhs)))
      }
      None => ()
    }
  }

  let div_eq_idx = awk_find_top_level_token(text, "/=")
  if div_eq_idx > 0 {
    let lhs = aj_substr(text, 0, div_eq_idx)
    match awk_parse_assign_target(lhs) {
      Some(lhs_target) => {
        let rhs = aj_trim(aj_substr(text, div_eq_idx + 2, text.length()))
        return Some((lhs_target, "/=", awk_parse_expr_ast(rhs)))
      }
      None => ()
    }
  }

  None
}

fn awk_parse_assign_stmt(text : String) -> (AwkAssignTarget, AwkExprAst)? {
  let eq_idx = awk_find_top_level_token(text, "=")
  if eq_idx <= 0 {
    return None
  }
  let prev = text[eq_idx - 1].to_int().unsafe_to_char()
  let next = if eq_idx + 1 < text.length() {
    Some(text[eq_idx + 1].to_int().unsafe_to_char())
  } else {
    None
  }
  if prev == '!' || prev == '<' || prev == '>' || prev == '=' || next == Some('=') {
    return None
  }
  let lhs = aj_substr(text, 0, eq_idx)
  let lhs_target = match awk_parse_assign_target(lhs) {
    Some(target) => target
    None => return None
  }
  let rhs = aj_trim(aj_substr(text, eq_idx + 1, text.length()))
  Some((lhs_target, awk_parse_expr_ast(rhs)))
}

fn awk_parse_field_assign_stmt(text : String) -> (String, AwkExprAst)? {
  let eq_idx = awk_find_top_level_token(text, "=")
  if eq_idx <= 0 {
    return None
  }
  let prev = text[eq_idx - 1].to_int().unsafe_to_char()
  let next = if eq_idx + 1 < text.length() {
    Some(text[eq_idx + 1].to_int().unsafe_to_char())
  } else {
    None
  }
  if prev == '!' || prev == '<' || prev == '>' || prev == '=' || next == Some('=') {
    return None
  }
  let lhs = aj_trim(aj_substr(text, 0, eq_idx))
  if not(aj_starts_with(lhs, "$")) {
    return None
  }
  let rhs = aj_trim(aj_substr(text, eq_idx + 1, text.length()))
  Some((lhs, awk_parse_expr_ast(rhs)))
}

fn awk_parse_statement_ast(stmt : String) -> AwkStmt {
  let text = aj_trim(stmt)
  if text.length() == 0 {
    return ExprStmt(Raw(""))
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
    return PipeGetline(awk_parse_expr_ast(cmd_expr), awk_parse_getline_target(target))
  }

  if text == "getline" || aj_starts_with(text, "getline ") {
    let tail = if text.length() > 7 { aj_trim(aj_substr(text, 7, text.length())) } else { "" }
    let read_from_file_idx = awk_find_top_level_token(tail, "<")
    if read_from_file_idx > 0 {
      let target = aj_trim(aj_substr(tail, 0, read_from_file_idx))
      let path_expr = aj_trim(aj_substr(tail, read_from_file_idx + 1, tail.length()))
      return Getline(awk_parse_getline_target(target), Some(awk_parse_expr_ast(path_expr)))
    }
    return Getline(awk_parse_getline_target(tail), None)
  }

  if aj_starts_with(text, "system(") && aj_ends_with(text, ")") {
    return SystemStmt
  }

  let is_gsub = aj_starts_with(text, "gsub(") && aj_ends_with(text, ")")
  let is_sub = aj_starts_with(text, "sub(") && aj_ends_with(text, ")")
  if is_gsub || is_sub {
    let offset = if is_gsub { 5 } else { 4 }
    let inner = aj_substr(text, offset, text.length() - 1)
    let args_ast : Array[AwkExprAst] = []
    for arg in awk_split_csv_args(inner) {
      args_ast.push(awk_parse_expr_ast(arg))
    }
    return SubstituteStmt(is_gsub, args_ast)
  }

  if aj_starts_with(text, "delete ") {
    let target_expr = aj_trim(aj_substr(text, 6, text.length()))
    return match awk_parse_array_ref(target_expr) {
      Some((arr_name, idx_expr)) => Delete(arr_name, Some(awk_parse_expr_ast(idx_expr)))
      None => Delete(target_expr, None)
    }
  }

  if aj_starts_with(text, "printf") {
    let rest = aj_trim(aj_substr(text, 6, text.length()))
    let (printf_expr, target_expr, append) = match awk_parse_print_redirection(rest) {
      Some(parsed) => parsed
      None => (rest, "", false)
    }
    let (fmt_expr, arg_exprs) = awk_parse_printf("printf " + printf_expr)
    let fmt_ast = awk_parse_expr_ast(fmt_expr)
    let args_ast : Array[AwkExprAst] = []
    for expr in arg_exprs {
      args_ast.push(awk_parse_expr_ast(expr))
    }
    let target_ast = if target_expr.length() > 0 {
      Some(awk_parse_expr_ast(target_expr))
    } else {
      None
    }
    return Printf(fmt_ast, args_ast, target_ast, append)
  }

  if aj_starts_with(text, "print") && not(aj_starts_with(text, "printf")) {
    let rest = aj_trim(aj_substr(text, 5, text.length()))
    let has_pipe = awk_find_top_level_token(rest, "|") >= 0
    let (value_expr, target_expr, append) = match awk_parse_print_redirection(rest) {
      Some(parsed) => parsed
      None => (rest, "", false)
    }
    let value_asts : Array[AwkExprAst] = []
    if value_expr.length() > 0 {
      for expr in awk_split_csv_args(value_expr) {
        value_asts.push(awk_parse_expr_ast(expr))
      }
    }
    let target_ast = if target_expr.length() > 0 {
      Some(awk_parse_expr_ast(target_expr))
    } else {
      None
    }
    return Print(value_asts, target_ast, append, has_pipe)
  }

  match awk_parse_compound_assign_stmt(text) {
    Some((lhs_target, op, rhs_ast)) => return CompoundAssignStmt(lhs_target, op, rhs_ast)
    None => ()
  }

  match awk_parse_field_assign_stmt(text) {
    Some((lhs, rhs_ast)) => return FieldAssignStmt(lhs, rhs_ast)
    None => ()
  }

  match awk_parse_assign_stmt(text) {
    Some((lhs_target, rhs_ast)) => return AssignStmt(lhs_target, rhs_ast)
    None => ()
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

  match awk_parse_while_statement(text) {
    Some((cond_expr, body_stmt)) => {
      let cond_ast = awk_parse_expr_ast(cond_expr)
      let body_ast = awk_parse_action_ast(body_stmt)
      return While(cond_ast, body_ast)
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
    None => ExprStmt(awk_parse_expr_ast(text))
  }
}

fn awk_parse_action_ast(action : String) -> Array[AwkStmt] {
  let merged = awk_merge_if_else_statements(awk_split_statements(action))
  let out : Array[AwkStmt] = []
  for stmt_raw in merged {
    if aj_trim(stmt_raw).length() == 0 {
      continue
    }
    let stmt = awk_parse_statement_ast(stmt_raw)
    out.push(stmt)
  }
  out
}
