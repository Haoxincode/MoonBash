// moon_bash Commands - awk expression evaluator (awk_eval_expr)

fn awk_eval_expr(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let ast = awk_parse_expr_ast(expr)
  awk_eval_expr_ast(ast, line, fields, nr, nf, vars, array_vars)
}

fn awk_eval_expr_legacy(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let t = awk_strip_outer_parens(aj_trim(expr))
  if t.length() == 0 {
    return ""
  }

  if aj_ends_with(t, "++") || aj_ends_with(t, "--") {
    let target = aj_trim(aj_substr(t, 0, t.length() - 2))
    let delta = if aj_ends_with(t, "++") { 1.0 } else { -1.0 }
    match awk_mutate_numeric_reference(
      target,
      delta,
      false,
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    ) {
      Some(value) => return value
      None => ()
    }
  }

  if aj_starts_with(t, "++") || aj_starts_with(t, "--") {
    let target = aj_trim(aj_substr(t, 2, t.length()))
    let delta = if aj_starts_with(t, "++") { 1.0 } else { -1.0 }
    match awk_mutate_numeric_reference(
      target,
      delta,
      true,
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    ) {
      Some(value) => return value
      None => ()
    }
  }

  match awk_parse_call_expr(t) {
    Some((call_name, args)) =>
      return awk_eval_call_expr_ast(call_name, args, line, fields, nr, nf, vars, array_vars)
    None => ()
  }

  let tokens = awk_tokenize_expr(t)
  if tokens.length() > 1 {
    let out = StringBuilder::new()
    for tok in tokens {
      out.write_string(awk_eval_expr(tok, line, fields, nr, nf, vars, array_vars))
    }
    return out.to_string()
  }

  awk_eval_atom(t, line, fields, nr, nf, vars, array_vars)
}
