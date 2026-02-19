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
  let t = awk_strip_outer_parens(aj_trim(expr))
  let tokens = awk_tokenize_expr(t)
  if tokens.length() == 0 {
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
    Some((call_name, args)) => {
      if call_name == "index" {
        if args.length() < 2 {
          return "0"
        }
        let haystack = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        let needle = awk_eval_expr(
          args[1],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        if needle.length() == 0 {
          return "1"
        }
        let idx = aj_find_substring(haystack, needle)
        return if idx >= 0 { (idx + 1).to_string() } else { "0" }
      }

      if call_name == "substr" {
        if args.length() < 2 {
          return ""
        }
        let text = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        let raw_start = awk_eval_number(
          args[1],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        ).to_int()
        let start_pos = if raw_start <= 1 { 1 } else { raw_start }
        let start_idx = start_pos - 1
        if start_idx >= text.length() {
          return ""
        }
        if args.length() >= 3 {
          let len = awk_eval_number(
            args[2],
            line,
            fields,
            nr,
            nf,
            vars,
            array_vars,
          ).to_int()
          if len <= 0 {
            return ""
          }
          return aj_substr(text, start_idx, start_idx + len)
        }
        return aj_substr(text, start_idx, text.length())
      }

      if call_name == "tolower" {
        if args.length() == 0 {
          return ""
        }
        let value = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        return awk_to_lower(value)
      }

      if call_name == "toupper" {
        if args.length() == 0 {
          return ""
        }
        let value = awk_eval_expr(
          args[0],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
        return awk_to_upper(value)
      }

      if call_name == "close" {
        return "0"
      }

      if call_name == "sin" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.sin(value))
      }

      if call_name == "cos" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.cos(value))
      }

      if call_name == "exp" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.exp(value))
      }

      if call_name == "log" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(@math.ln(value))
      }

      if call_name == "sqrt" {
        let value = if args.length() > 0 {
          awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        } else {
          0.0
        }
        return awk_number_to_string(value.sqrt())
      }

      if call_name == "atan2" {
        if args.length() < 2 {
          return "0"
        }
        let y = awk_eval_number(args[0], line, fields, nr, nf, vars, array_vars)
        let x = awk_eval_number(args[1], line, fields, nr, nf, vars, array_vars)
        let pi = @math.atan(1.0) * 4.0
        let half_pi = pi / 2.0
        let angle = if x > 0.0 {
          @math.atan(y / x)
        } else if x < 0.0 && y >= 0.0 {
          @math.atan(y / x) + pi
        } else if x < 0.0 {
          @math.atan(y / x) - pi
        } else if y > 0.0 {
          half_pi
        } else if y < 0.0 {
          -half_pi
        } else {
          0.0
        }
        return awk_number_to_string(angle)
      }

      match awk_get_function(vars, call_name) {
        Some(_) => {
          let fn_out = StringBuilder::new()
          return awk_eval_user_function(
            call_name,
            args,
            line,
            fields,
            nr,
            nf,
            vars,
            array_vars,
            fn_out,
          )
        }
        None => ()
      }
    }
    None => ()
  }

  if aj_starts_with(t, "sprintf(") && aj_ends_with(t, ")") {
    let inner = aj_substr(t, 8, t.length() - 1)
    let args = awk_split_csv_args(inner)
    if args.length() == 0 {
      return ""
    }
    let format = awk_eval_expr(
      args[0],
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let format_args : Array[String] = []
    for i = 1; i < args.length(); i = i + 1 {
      format_args.push(
        awk_eval_expr(
          args[i],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        ),
      )
    }
    return awk_format_printf(format, format_args)
  }

  if aj_starts_with(t, "split(") && aj_ends_with(t, ")") {
    let inner = aj_substr(t, 6, t.length() - 1)
    let args = awk_split_csv_args(inner)
    if args.length() >= 2 {
      let source = awk_eval_expr(
        args[0],
        line,
        fields,
        nr,
        nf,
        vars,
        array_vars,
      )
      let arr_name = aj_trim(args[1])
      let delim = if args.length() >= 3 {
        awk_eval_split_delim(
          args[2],
          line,
          fields,
          nr,
          nf,
          vars,
          array_vars,
        )
      } else {
        awk_current_fs(vars.get("FS").unwrap_or(" "), vars)
      }
      let pieces = awk_split_for_split_builtin(source, delim)
      for i = 0; i < pieces.length(); i = i + 1 {
        array_vars[awk_array_key(arr_name, (i + 1).to_string())] = pieces[i]
      }
      vars[arr_name] = pieces.length().to_string()
      return pieces.length().to_string()
    }
    return "0"
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
      let rhs = aj_trim(aj_substr(t, eq_idx + 1, t.length()))
      let value = awk_eval_expr(rhs, line, fields, nr, nf, vars, array_vars)
      if awk_assign_reference(lhs, value, line, fields, nr, nf, vars, array_vars) {
        return value
      }
    }
  }

  let in_idx = awk_find_top_level_token(t, " in ")
  if in_idx > 0 {
    let left_expr = aj_substr(t, 0, in_idx)
    let right_expr = aj_trim(aj_substr(t, in_idx + 4, t.length()))
    if awk_is_identifier(right_expr) {
      let idx_value = awk_eval_expr(
        left_expr,
        line,
        fields,
        nr,
        nf,
        vars,
        array_vars,
      )
      return awk_bool_to_string(array_vars.contains(awk_array_key(right_expr, idx_value)))
    }
  }

  let comma_idx = awk_find_top_level_token(t, ",")
  if comma_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, comma_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, comma_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let subsep = vars.get("SUBSEP").unwrap_or("\u001c")
    return left + subsep + right
  }

  let question_idx = awk_find_top_level_token(t, "?")
  if question_idx > 0 {
    let colon_idx = awk_find_top_level_ternary_colon(t, question_idx + 1)
    if colon_idx > question_idx {
      let cond_expr = aj_substr(t, 0, question_idx)
      let true_expr = aj_substr(t, question_idx + 1, colon_idx)
      let false_expr = aj_substr(t, colon_idx + 1, t.length())
      if awk_eval_condition(cond_expr, line, fields, nr, nf, vars, array_vars) {
        return awk_eval_expr(true_expr, line, fields, nr, nf, vars, array_vars)
      } else {
        return awk_eval_expr(false_expr, line, fields, nr, nf, vars, array_vars)
      }
    }
  }

  let or_idx = awk_find_top_level_token(t, "||")
  if or_idx > 0 {
    let left_value = awk_eval_expr(
      aj_substr(t, 0, or_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if awk_value_truthy(left_value) {
      return "1"
    }
    let right_value = awk_eval_expr(
      aj_substr(t, or_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_value_truthy(right_value))
  }

  let and_idx = awk_find_top_level_token(t, "&&")
  if and_idx > 0 {
    let left_value = awk_eval_expr(
      aj_substr(t, 0, and_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if not(awk_value_truthy(left_value)) {
      return "0"
    }
    let right_value = awk_eval_expr(
      aj_substr(t, and_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_value_truthy(right_value))
  }

  let not_match_idx = awk_find_top_level_token(t, "!~")
  if not_match_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, not_match_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right_expr = aj_trim(aj_substr(t, not_match_idx + 2, t.length()))
    let right = if aj_starts_with(right_expr, "/") && aj_ends_with(right_expr, "/") {
      right_expr
    } else {
      "/" + awk_eval_expr(right_expr, line, fields, nr, nf, vars, array_vars) + "/"
    }
    let (rstart, _rlength) = awk_find_regex_match_range(right, left)
    return awk_bool_to_string(rstart <= 0)
  }

  let match_idx = awk_find_top_level_token(t, "~")
  if match_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, match_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right_expr = aj_trim(aj_substr(t, match_idx + 1, t.length()))
    let right = if aj_starts_with(right_expr, "/") && aj_ends_with(right_expr, "/") {
      right_expr
    } else {
      "/" + awk_eval_expr(right_expr, line, fields, nr, nf, vars, array_vars) + "/"
    }
    let (rstart, _rlength) = awk_find_regex_match_range(right, left)
    return awk_bool_to_string(rstart > 0)
  }

  let mut cmp_idx = awk_find_top_level_token(t, "==")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "=="))
  }

  cmp_idx = awk_find_top_level_token(t, "!=")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "!="))
  }

  cmp_idx = awk_find_top_level_token(t, ">=")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, ">="))
  }

  cmp_idx = awk_find_top_level_token(t, "<=")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 2, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "<="))
  }

  cmp_idx = awk_find_top_level_token(t, ">")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, ">"))
  }

  cmp_idx = awk_find_top_level_token(t, "<")
  if cmp_idx > 0 {
    let left = awk_eval_expr(
      aj_substr(t, 0, cmp_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_expr(
      aj_substr(t, cmp_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_bool_to_string(awk_compare_values(left, right, "<"))
  }

  let pow_idx = awk_find_top_level_token(t, "^")
  if pow_idx > 0 {
    let left = awk_eval_number(
      aj_substr(t, 0, pow_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(t, pow_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    return awk_number_to_string(@math.pow(left, right))
  }

  let add_sub_idx = awk_find_top_level_operator(t, "+-")
  if add_sub_idx > 0 {
    let op = t[add_sub_idx].to_int().unsafe_to_char()
    let left = awk_eval_number(
      aj_substr(t, 0, add_sub_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(t, add_sub_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let value = if op == '+' { left + right } else { left - right }
    return awk_number_to_string(value)
  }

  let mul_div_idx = awk_find_top_level_operator(t, "*/%")
  if mul_div_idx > 0 {
    let op = t[mul_div_idx].to_int().unsafe_to_char()
    let left = awk_eval_number(
      aj_substr(t, 0, mul_div_idx),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    let right = awk_eval_number(
      aj_substr(t, mul_div_idx + 1, t.length()),
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
    )
    if op == '*' {
      return awk_number_to_string(left * right)
    }
    if op == '%' {
      if right == 0.0 {
        return "0"
      }
      let left_i = left.to_int()
      let right_i = right.to_int()
      if right_i == 0 {
        return "0"
      }
      return (left_i % right_i).to_string()
    }
    if right == 0.0 {
      return "0"
    }
    return (left / right).to_string()
  }

  if tokens.length() > 1 {
    let out = StringBuilder::new()
    for tok in tokens {
      out.write_string(awk_eval_expr(tok, line, fields, nr, nf, vars, array_vars))
    }
    return out.to_string()
  }

  awk_eval_atom(t, line, fields, nr, nf, vars, array_vars)
}

