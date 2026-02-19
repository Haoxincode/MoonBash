// moon_bash Commands - awk atom evaluation, tokenizer, function execution, comparison

fn awk_eval_atom(
  atom : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String {
  let t = aj_trim(atom)
  if t.length() == 0 {
    return ""
  }

  if (aj_starts_with(t, "\"") && aj_ends_with(t, "\"")) ||
    (aj_starts_with(t, "'") && aj_ends_with(t, "'")) {
    return aj_decode_c_escapes(aj_substr(t, 1, t.length() - 1))
  }

  if t == "NR" {
    return vars.get("NR").unwrap_or(nr.to_string())
  }
  if t == "NF" {
    return vars.get("NF").unwrap_or(nf.to_string())
  }
  if t == "FNR" {
    return vars.get("FNR").unwrap_or(nr.to_string())
  }
  if t == "FILENAME" {
    return vars.get("FILENAME").unwrap_or("")
  }
  if t == "RSTART" {
    return vars.get("RSTART").unwrap_or("0")
  }
  if t == "RLENGTH" {
    return vars.get("RLENGTH").unwrap_or("-1")
  }
  if t == "FS" {
    return vars.get("FS").unwrap_or("")
  }

  if aj_starts_with(t, "$") {
    let key_expr = aj_substr(t, 1, t.length())
    if key_expr == "0" {
      return line
    }
    let key_value = if key_expr == "NF" {
      fields.length().to_string()
    } else if awk_is_numeric_string(key_expr) {
      awk_number_to_string(awk_parse_number(key_expr))
    } else {
      awk_eval_expr(key_expr, line, fields, nr, nf, vars, array_vars)
    }
    if key_value == "NF" {
      return if fields.length() == 0 { "" } else { fields[fields.length() - 1] }
    } else {
      let idx = awk_parse_number(key_value).to_int()
      if idx >= 1 && idx <= fields.length() {
        return fields[idx - 1]
      } else {
        return ""
      }
    }
  }

  match awk_parse_array_ref(t) {
    Some((arr_name, idx_expr)) => {
      let idx = awk_eval_expr(
        idx_expr,
        line,
        fields,
        nr,
        nf,
        vars,
        array_vars,
      )
      return array_vars.get(awk_array_key(arr_name, idx)).unwrap_or("")
    }
    None => ()
  }

  if awk_is_numeric_string(t) {
    return t
  }

  if awk_is_identifier(t) {
    return vars.get(t).unwrap_or("")
  }

  ""
}

fn awk_tokenize_expr(expr : String) -> Array[String] {
  let tokens : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  let mut paren_depth = 0
  let mut bracket_depth = 0
  for i = 0; i < expr.length(); i = i + 1 {
    let ch = expr[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          buf.write_char(ch)
        } else if ch == '(' {
          paren_depth += 1
          buf.write_char(ch)
        } else if ch == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == '[' {
          bracket_depth += 1
          buf.write_char(ch)
        } else if ch == ']' {
          if bracket_depth > 0 {
            bracket_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == ' ' || ch == '\t' {
          if paren_depth == 0 && bracket_depth == 0 {
            let tok = buf.to_string()
            if tok.length() > 0 {
              tokens.push(tok)
              buf.reset()
            }
          } else {
            buf.write_char(ch)
          }
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    tokens.push(last)
  }
  tokens
}

fn awk_eval_number(
  expr : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> Double {
  let value = awk_eval_expr(expr, line, fields, nr, nf, vars, array_vars)
  awk_parse_number(value)
}

fn awk_execute_function_body(
  body : String,
  line : String,
  fields : Array[String],
  nr : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> Unit {
  let statements = awk_parse_action_ast(body)
  awk_execute_function_statements(statements, line, fields, nr, vars, array_vars, out)
}

fn awk_execute_function_statements(
  statements : Array[AwkStmt],
  line : String,
  fields : Array[String],
  nr : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> Unit {
  for stmt in statements {
    if vars.contains(awk_ctrl_exit_key) ||
      vars.contains(awk_ctrl_next_key) ||
      vars.contains(awk_ctrl_return_key) {
      break
    }
    match stmt {
      Next => {
        vars[awk_ctrl_next_key] = "1"
        break
      }
      Exit(code_ast) => {
        let code = match code_ast {
          Some(expr_ast) =>
            awk_parse_number(
              awk_eval_expr_ast(expr_ast, line, fields, nr, fields.length(), vars, array_vars),
            ).to_int()
          None => 0
        }
        vars[awk_ctrl_exit_key] = code.to_string()
        break
      }
      Return(value_ast) => {
        let value = match value_ast {
          Some(expr_ast) =>
            awk_eval_expr_ast(expr_ast, line, fields, nr, fields.length(), vars, array_vars)
          None => ""
        }
        vars[awk_ctrl_return_key] = "1"
        vars[awk_ctrl_return_value_key] = value
        break
      }
      PipeGetline(_cmd_ast, _target) => {
        ()
      }
      Getline(_tail) => {
        ()
      }
      Delete(_target_expr) => {
        ()
      }
      Printf(rest) => {
        let (fmt_expr, arg_exprs) = awk_parse_printf("printf " + rest)
        let fmt_value = awk_eval_expr(fmt_expr, line, fields, nr, fields.length(), vars, array_vars)
        let fmt_args : Array[String] = []
        for expr in arg_exprs {
          fmt_args.push(awk_eval_expr(expr, line, fields, nr, fields.length(), vars, array_vars))
        }
        out.write_string(awk_format_printf(fmt_value, fmt_args))
      }
      Print(rest) => {
        out.write_string(
          awk_render_print_output(
            rest,
            line,
            fields,
            nr,
            vars,
            array_vars,
          ),
        )
      }
      ForIn(loop_var, arr_name, body_stmts) => {
        let key_prefix = arr_name + "#"
        let indices : Array[String] = []
        for key, _value in array_vars {
          if aj_starts_with(key, key_prefix) {
            indices.push(aj_substr(key, key_prefix.length(), key.length()))
          }
        }
        for idx_value in indices {
          if vars.contains(awk_ctrl_exit_key) ||
            vars.contains(awk_ctrl_next_key) ||
            vars.contains(awk_ctrl_return_key) {
            break
          }
          vars[loop_var] = idx_value
          if body_stmts.length() > 0 {
            awk_execute_function_statements(body_stmts, line, fields, nr, vars, array_vars, out)
          }
        }
      }
      For(init_stmts, cond_ast, update_stmts, body_stmts) => {
        if init_stmts.length() > 0 {
          awk_execute_function_statements(init_stmts, line, fields, nr, vars, array_vars, out)
        }
        let mut loop_count = 0
        while true {
          if vars.contains(awk_ctrl_exit_key) ||
            vars.contains(awk_ctrl_next_key) ||
            vars.contains(awk_ctrl_return_key) {
            break
          }
          match cond_ast {
            Some(cond_expr_ast) => {
              if not(
                awk_eval_condition_ast(
                  cond_expr_ast,
                  line,
                  fields,
                  nr,
                  fields.length(),
                  vars,
                  array_vars,
                ),
              ) {
                break
              }
            }
            None => ()
          }
          if body_stmts.length() > 0 {
            awk_execute_function_statements(body_stmts, line, fields, nr, vars, array_vars, out)
          }
          if vars.contains(awk_ctrl_exit_key) ||
            vars.contains(awk_ctrl_next_key) ||
            vars.contains(awk_ctrl_return_key) {
            break
          }
          if update_stmts.length() > 0 {
            awk_execute_function_statements(update_stmts, line, fields, nr, vars, array_vars, out)
          }
          loop_count += 1
          if loop_count > awk_loop_guard_limit {
            break
          }
        }
      }
      If(cond_ast, then_stmts, else_stmts) => {
        if awk_eval_condition_ast(
          cond_ast,
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
        ) {
          awk_execute_function_statements(then_stmts, line, fields, nr, vars, array_vars, out)
        } else {
          match else_stmts {
            Some(else_branch) =>
              awk_execute_function_statements(else_branch, line, fields, nr, vars, array_vars, out)
            None => ()
          }
        }
      }
      Simple(raw_stmt) => {
        awk_execute_function_body_simple(raw_stmt, line, fields, nr, vars, array_vars, out)
      }
    }
  }
}

fn awk_execute_function_body_simple(
  body : String,
  line : String,
  fields : Array[String],
  nr : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> Unit {
  let statements = awk_merge_if_else_statements(awk_split_statements(body))
  for stmt_raw in statements {
    if vars.contains(awk_ctrl_exit_key) || vars.contains(awk_ctrl_return_key) {
      break
    }
    let stmt = aj_trim(stmt_raw)
    if stmt.length() == 0 {
      continue
    }

    if aj_starts_with(stmt, "print") {
      let rest = aj_trim(aj_substr(stmt, 5, stmt.length()))
      out.write_string(
        awk_render_print_output(
          rest,
          line,
          fields,
          nr,
          vars,
          array_vars,
        ),
      )
      continue
    }

    let plus_eq_idx = awk_find_top_level_token(stmt, "+=")
    if plus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, plus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, plus_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        line,
        fields,
        nr,
        fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(left + right)
      } else {
        match awk_parse_array_ref(name) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              line,
              fields,
              nr,
              fields.length(),
              vars,
              array_vars,
            )
            let key = awk_array_key(arr_name, idx)
            let left = awk_parse_number(array_vars.get(key).unwrap_or(""))
            array_vars[key] = awk_number_to_string(left + right)
          }
          None => ()
        }
      }
      continue
    }

    let eq_idx = awk_find_top_level_token(stmt, "=")
    if eq_idx > 0 {
      let prev = stmt[eq_idx - 1].to_int().unsafe_to_char()
      let next = if eq_idx + 1 < stmt.length() {
        Some(stmt[eq_idx + 1].to_int().unsafe_to_char())
      } else {
        None
      }
      if prev != '!' && prev != '<' && prev != '>' && prev != '=' &&
        next != Some('=') {
        let lhs = aj_trim(aj_substr(stmt, 0, eq_idx))
        let rhs = aj_trim(aj_substr(stmt, eq_idx + 1, stmt.length()))
        let value = awk_eval_expr(rhs, line, fields, nr, fields.length(), vars, array_vars)
        if awk_is_identifier(lhs) {
          vars[lhs] = value
        } else {
          match awk_parse_array_ref(lhs) {
            Some((arr_name, idx_expr)) => {
              let idx = awk_eval_expr(
                idx_expr,
                line,
                fields,
                nr,
                fields.length(),
                vars,
                array_vars,
              )
              array_vars[awk_array_key(arr_name, idx)] = value
            }
            None => ()
          }
        }
      }
      continue
    }

    match awk_parse_call_expr(stmt) {
      Some((call_name, args)) => {
        if call_name == "close" {
          continue
        }
        if call_name == "sprintf" {
          ignore(awk_eval_expr(stmt, line, fields, nr, fields.length(), vars, array_vars))
          continue
        }
        ignore(awk_eval_user_function(
          call_name,
          args,
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
          out,
        ))
        continue
      }
      None => ()
    }
  }
}

fn awk_eval_user_function(
  fn_name : String,
  arg_exprs : Array[String],
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> String {
  ignore(nf)
  let fn_def = match awk_get_function(vars, fn_name) {
    Some(def) => def
    None => return ""
  }

  let saved_scalars : Array[(String, String?)] = []
  let array_bindings : Array[(String, String)] = []
  for i = 0; i < fn_def.params.length(); i = i + 1 {
    let param = fn_def.params[i]
    saved_scalars.push((param, vars.get(param)))
    if i < arg_exprs.length() {
      let arg_expr = aj_trim(arg_exprs[i])
      if awk_is_identifier(arg_expr) && awk_function_param_is_array(fn_def, param) {
        array_bindings.push((param, arg_expr))
        awk_copy_array_namespace(array_vars, arg_expr, param)
        vars[param] = ""
      } else {
        vars[param] = awk_eval_expr(
          arg_expr,
          line,
          fields,
          nr,
          fields.length(),
          vars,
          array_vars,
        )
      }
    } else {
      vars[param] = ""
    }
  }

  vars.remove(awk_ctrl_return_key)
  vars.remove(awk_ctrl_return_value_key)
  awk_execute_function_body(fn_def.body, line, fields, nr, vars, array_vars, out)
  let return_value = vars.get(awk_ctrl_return_value_key).unwrap_or("")
  vars.remove(awk_ctrl_return_key)
  vars.remove(awk_ctrl_return_value_key)

  for binding in array_bindings {
    let local_name = binding.0
    let actual_name = binding.1
    awk_remove_array_namespace(array_vars, actual_name)
    awk_copy_array_namespace(array_vars, local_name, actual_name)
    awk_remove_array_namespace(array_vars, local_name)
  }

  for saved in saved_scalars {
    match saved.1 {
      Some(v) => vars[saved.0] = v
      None => vars.remove(saved.0)
    }
  }

  return_value
}

fn awk_bool_to_string(value : Bool) -> String {
  if value { "1" } else { "0" }
}

fn awk_compare_strings(left : String, right : String) -> Int {
  let shared = if left.length() < right.length() { left.length() } else { right.length() }
  for i = 0; i < shared; i = i + 1 {
    let lch = left[i].to_int().unsafe_to_char()
    let rch = right[i].to_int().unsafe_to_char()
    if lch < rch {
      return -1
    }
    if lch > rch {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

fn awk_compare_values(left : String, right : String, op : String) -> Bool {
  if awk_is_numeric_string(left) && awk_is_numeric_string(right) {
    let lnum = awk_parse_number(left)
    let rnum = awk_parse_number(right)
    match op {
      "==" => lnum == rnum
      "!=" => lnum != rnum
      ">=" => lnum >= rnum
      "<=" => lnum <= rnum
      ">" => lnum > rnum
      "<" => lnum < rnum
      _ => false
    }
  } else {
    let cmp = awk_compare_strings(left, right)
    match op {
      "==" => cmp == 0
      "!=" => cmp != 0
      ">=" => cmp >= 0
      "<=" => cmp <= 0
      ">" => cmp > 0
      "<" => cmp < 0
      _ => false
    }
  }
}

fn awk_value_truthy(value : String) -> Bool {
  if awk_is_numeric_string(value) {
    awk_parse_number(value) != 0.0
  } else {
    value.length() > 0
  }
}

fn awk_assign_reference(
  target : String,
  value : String,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> Bool {
  if awk_is_identifier(target) {
    vars[target] = value
    return true
  }
  match awk_parse_array_ref(target) {
    Some((arr_name, idx_expr)) => {
      let idx = awk_eval_expr(idx_expr, line, fields, nr, nf, vars, array_vars)
      array_vars[awk_array_key(arr_name, idx)] = value
      true
    }
    None => false
  }
}

fn awk_mutate_numeric_reference(
  target : String,
  delta : Double,
  return_new : Bool,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  vars : Map[String, String],
  array_vars : Map[String, String]
) -> String? {
  if awk_is_identifier(target) {
    let old = awk_parse_number(vars.get(target).unwrap_or(""))
    let updated = old + delta
    vars[target] = awk_number_to_string(updated)
    return Some(if return_new { vars[target] } else { awk_number_to_string(old) })
  }
  if aj_starts_with(target, "$") && target.length() > 1 {
    let key_expr = aj_substr(target, 1, target.length())
    let key_value = if key_expr == "NF" {
      fields.length().to_string()
    } else {
      awk_eval_expr(key_expr, line, fields, nr, nf, vars, array_vars)
    }
    let idx = awk_parse_number(key_value).to_int()
    if idx > 0 {
      while fields.length() < idx {
        fields.push("")
      }
      let old = awk_parse_number(fields[idx - 1])
      let updated = old + delta
      fields[idx - 1] = awk_number_to_string(updated)
      return Some(if return_new { fields[idx - 1] } else { awk_number_to_string(old) })
    }
  }
  match awk_parse_array_ref(target) {
    Some((arr_name, idx_expr)) => {
      let idx = awk_eval_expr(idx_expr, line, fields, nr, nf, vars, array_vars)
      let key = awk_array_key(arr_name, idx)
      let old = awk_parse_number(array_vars.get(key).unwrap_or(""))
      let updated = old + delta
      array_vars[key] = awk_number_to_string(updated)
      Some(if return_new { array_vars.get(key).unwrap_or("") } else { awk_number_to_string(old) })
    }
    None => None
  }
}
