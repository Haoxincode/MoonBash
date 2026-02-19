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
