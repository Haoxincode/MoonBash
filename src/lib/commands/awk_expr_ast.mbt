// moon_bash Commands - awk expression AST parser/evaluator

priv enum AwkExprAst {
  Raw(String)
  UnaryNot(AwkExprAst)
  Concat(Array[AwkExprAst])
  Ternary(AwkExprAst, AwkExprAst, AwkExprAst)
  Assign(String, AwkExprAst)
  In(AwkExprAst, String)
  Binary(String, AwkExprAst, AwkExprAst)
} derive(Show)

fn awk_expr_assignment_target_valid(lhs : String) -> Bool {
  let t = aj_trim(lhs)
  if awk_is_identifier(t) {
    return true
  }
  match awk_parse_array_ref(t) {
    Some(_) => true
    None => false
  }
}

fn awk_parse_expr_ast(expr : String) -> AwkExprAst {
  let t = awk_strip_outer_parens(aj_trim(expr))
  if t.length() == 0 {
    return Raw("")
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
      if awk_expr_assignment_target_valid(lhs) {
        let rhs = aj_trim(aj_substr(t, eq_idx + 1, t.length()))
        return Assign(lhs, awk_parse_expr_ast(rhs))
      }
    }
  }

  let in_idx = awk_find_top_level_token(t, " in ")
  if in_idx > 0 {
    let left_expr = aj_substr(t, 0, in_idx)
    let right_expr = aj_trim(aj_substr(t, in_idx + 4, t.length()))
    if awk_is_identifier(right_expr) {
      return In(awk_parse_expr_ast(left_expr), right_expr)
    }
  }

  let comma_idx = awk_find_top_level_token(t, ",")
  if comma_idx > 0 {
    return Binary(
      ",",
      awk_parse_expr_ast(aj_substr(t, 0, comma_idx)),
      awk_parse_expr_ast(aj_substr(t, comma_idx + 1, t.length())),
    )
  }

  let question_idx = awk_find_top_level_token(t, "?")
  if question_idx > 0 {
    let colon_idx = awk_find_top_level_ternary_colon(t, question_idx + 1)
    if colon_idx > question_idx {
      let cond_expr = aj_substr(t, 0, question_idx)
      let true_expr = aj_substr(t, question_idx + 1, colon_idx)
      let false_expr = aj_substr(t, colon_idx + 1, t.length())
      return Ternary(
        awk_parse_expr_ast(cond_expr),
        awk_parse_expr_ast(true_expr),
        awk_parse_expr_ast(false_expr),
      )
    }
  }

  let or_idx = awk_find_top_level_token(t, "||")
  if or_idx > 0 {
    return Binary(
      "||",
      awk_parse_expr_ast(aj_substr(t, 0, or_idx)),
      awk_parse_expr_ast(aj_substr(t, or_idx + 2, t.length())),
    )
  }

  let and_idx = awk_find_top_level_token(t, "&&")
  if and_idx > 0 {
    return Binary(
      "&&",
      awk_parse_expr_ast(aj_substr(t, 0, and_idx)),
      awk_parse_expr_ast(aj_substr(t, and_idx + 2, t.length())),
    )
  }

  let not_match_idx = awk_find_top_level_token(t, "!~")
  if not_match_idx > 0 {
    return Binary(
      "!~",
      awk_parse_expr_ast(aj_substr(t, 0, not_match_idx)),
      awk_parse_expr_ast(aj_substr(t, not_match_idx + 2, t.length())),
    )
  }

  let match_idx = awk_find_top_level_token(t, "~")
  if match_idx > 0 {
    return Binary(
      "~",
      awk_parse_expr_ast(aj_substr(t, 0, match_idx)),
      awk_parse_expr_ast(aj_substr(t, match_idx + 1, t.length())),
    )
  }

  let mut cmp_idx = awk_find_top_level_token(t, "==")
  if cmp_idx > 0 {
    return Binary(
      "==",
      awk_parse_expr_ast(aj_substr(t, 0, cmp_idx)),
      awk_parse_expr_ast(aj_substr(t, cmp_idx + 2, t.length())),
    )
  }

  cmp_idx = awk_find_top_level_token(t, "!=")
  if cmp_idx > 0 {
    return Binary(
      "!=",
      awk_parse_expr_ast(aj_substr(t, 0, cmp_idx)),
      awk_parse_expr_ast(aj_substr(t, cmp_idx + 2, t.length())),
    )
  }

  cmp_idx = awk_find_top_level_token(t, ">=")
  if cmp_idx > 0 {
    return Binary(
      ">=",
      awk_parse_expr_ast(aj_substr(t, 0, cmp_idx)),
      awk_parse_expr_ast(aj_substr(t, cmp_idx + 2, t.length())),
    )
  }

  cmp_idx = awk_find_top_level_token(t, "<=")
  if cmp_idx > 0 {
    return Binary(
      "<=",
      awk_parse_expr_ast(aj_substr(t, 0, cmp_idx)),
      awk_parse_expr_ast(aj_substr(t, cmp_idx + 2, t.length())),
    )
  }

  cmp_idx = awk_find_top_level_token(t, ">")
  if cmp_idx > 0 {
    return Binary(
      ">",
      awk_parse_expr_ast(aj_substr(t, 0, cmp_idx)),
      awk_parse_expr_ast(aj_substr(t, cmp_idx + 1, t.length())),
    )
  }

  cmp_idx = awk_find_top_level_token(t, "<")
  if cmp_idx > 0 {
    return Binary(
      "<",
      awk_parse_expr_ast(aj_substr(t, 0, cmp_idx)),
      awk_parse_expr_ast(aj_substr(t, cmp_idx + 1, t.length())),
    )
  }

  let pow_idx = awk_find_top_level_token(t, "^")
  if pow_idx > 0 {
    return Binary(
      "^",
      awk_parse_expr_ast(aj_substr(t, 0, pow_idx)),
      awk_parse_expr_ast(aj_substr(t, pow_idx + 1, t.length())),
    )
  }

  let add_sub_idx = awk_find_top_level_operator(t, "+-")
  if add_sub_idx > 0 {
    let op = t[add_sub_idx].to_int().unsafe_to_char()
    return Binary(
      op.to_string(),
      awk_parse_expr_ast(aj_substr(t, 0, add_sub_idx)),
      awk_parse_expr_ast(aj_substr(t, add_sub_idx + 1, t.length())),
    )
  }

  let mul_div_idx = awk_find_top_level_operator(t, "*/%")
  if mul_div_idx > 0 {
    let op = t[mul_div_idx].to_int().unsafe_to_char()
    return Binary(
      op.to_string(),
      awk_parse_expr_ast(aj_substr(t, 0, mul_div_idx)),
      awk_parse_expr_ast(aj_substr(t, mul_div_idx + 1, t.length())),
    )
  }

  if aj_starts_with(t, "!") && t.length() > 1 {
    let next = t[1].to_int().unsafe_to_char()
    if next != '=' && next != '~' {
      return UnaryNot(awk_parse_expr_ast(aj_substr(t, 1, t.length())))
    }
  }

  let tokens = awk_tokenize_expr(t)
  if tokens.length() > 1 {
    let parts : Array[AwkExprAst] = []
    for tok in tokens {
      parts.push(awk_parse_expr_ast(tok))
    }
    return Concat(parts)
  }

  Raw(t)
}

fn awk_eval_expr_ast(
  ast : AwkExprAst,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  match ast {
    Raw(text) => awk_eval_expr_legacy(text, line, fields, nr, nf, vars, array_vars)
    UnaryNot(inner) =>
      awk_bool_to_string(
        not(awk_value_truthy(awk_eval_expr_ast(inner, line, fields, nr, nf, vars, array_vars))),
      )
    Concat(parts) => {
      let out = StringBuilder::new()
      for part in parts {
        out.write_string(awk_eval_expr_ast(part, line, fields, nr, nf, vars, array_vars))
      }
      out.to_string()
    }
    Ternary(cond, yes, no) => {
      let cond_value = awk_eval_expr_ast(cond, line, fields, nr, nf, vars, array_vars)
      if awk_value_truthy(cond_value) {
        awk_eval_expr_ast(yes, line, fields, nr, nf, vars, array_vars)
      } else {
        awk_eval_expr_ast(no, line, fields, nr, nf, vars, array_vars)
      }
    }
    Assign(lhs, rhs) => {
      let value = awk_eval_expr_ast(rhs, line, fields, nr, nf, vars, array_vars)
      if awk_assign_reference(lhs, value, line, fields, nr, nf, vars, array_vars) {
        value
      } else {
        awk_eval_expr_legacy(lhs + "=" + value, line, fields, nr, nf, vars, array_vars)
      }
    }
    In(left, arr_name) => {
      let idx_value = awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars)
      awk_bool_to_string(array_vars.contains(awk_array_key(arr_name, idx_value)))
    }
    Binary(op, left, right) => {
      if op == "," {
        let left_value = awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars)
        let right_value = awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars)
        let subsep = vars.get("SUBSEP").unwrap_or("\u001c")
        return left_value + subsep + right_value
      }

      if op == "||" {
        let left_value = awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars)
        if awk_value_truthy(left_value) {
          return "1"
        }
        let right_value = awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars)
        return awk_bool_to_string(awk_value_truthy(right_value))
      }

      if op == "&&" {
        let left_value = awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars)
        if not(awk_value_truthy(left_value)) {
          return "0"
        }
        let right_value = awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars)
        return awk_bool_to_string(awk_value_truthy(right_value))
      }

      if op == "~" || op == "!~" {
        let left_value = awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars)
        let right_raw = match right {
          Raw(text) => aj_trim(text)
          _ => ""
        }
        let pattern = if right_raw.length() >= 2 &&
          aj_starts_with(right_raw, "/") &&
          aj_ends_with(right_raw, "/") {
          right_raw
        } else {
          "/" + awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars) + "/"
        }
        let (rstart, _rlength) = awk_find_regex_match_range(pattern, left_value)
        return if op == "~" {
          awk_bool_to_string(rstart > 0)
        } else {
          awk_bool_to_string(rstart <= 0)
        }
      }

      if op == "==" || op == "!=" || op == ">=" || op == "<=" || op == ">" || op == "<" {
        let left_value = awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars)
        let right_value = awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars)
        return awk_bool_to_string(awk_compare_values(left_value, right_value, op))
      }

      if op == "^" {
        let left_n = awk_parse_number(awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars))
        let right_n = awk_parse_number(awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars))
        return awk_number_to_string(@math.pow(left_n, right_n))
      }

      if op == "+" || op == "-" {
        let left_n = awk_parse_number(awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars))
        let right_n = awk_parse_number(awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars))
        let value = if op == "+" { left_n + right_n } else { left_n - right_n }
        return awk_number_to_string(value)
      }

      if op == "*" || op == "/" || op == "%" {
        let left_n = awk_parse_number(awk_eval_expr_ast(left, line, fields, nr, nf, vars, array_vars))
        let right_n = awk_parse_number(awk_eval_expr_ast(right, line, fields, nr, nf, vars, array_vars))
        if op == "*" {
          return awk_number_to_string(left_n * right_n)
        }
        if op == "%" {
          if right_n == 0.0 {
            return "0"
          }
          let left_i = left_n.to_int()
          let right_i = right_n.to_int()
          if right_i == 0 {
            return "0"
          }
          return (left_i % right_i).to_string()
        }
        if right_n == 0.0 {
          return "0"
        }
        return (left_n / right_n).to_string()
      }

      awk_eval_expr_legacy("", line, fields, nr, nf, vars, array_vars)
    }
  }
}
