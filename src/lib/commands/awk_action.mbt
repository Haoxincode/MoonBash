// moon_bash Commands - awk action executor (awk_execute_action)

fn awk_execute_action(
  ctx : CommandContext,
  action : String,
  lines : Array[String],
  line_idx : Int,
  line : String,
  fields : Array[String],
  nr : Int,
  nf : Int,
  fs : String,
  filename : String,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> (String, Array[String], Int, Int) {
  ignore(nf)
  let act = aj_trim(action)
  if act.length() == 0 {
    out.write_string(line)
    out.write_char('\n')
    return (line, fields, 0, nr)
  }
  let statements = awk_parse_action_ast(act)
  awk_execute_action_ast_list(
    ctx,
    statements,
    lines,
    line_idx,
    line,
    fields,
    nr,
    fs,
    filename,
    vars,
    array_vars,
    out,
  )
}

fn awk_execute_empty_action_branch(
  line : String,
  fields : Array[String],
  nr : Int,
  out : StringBuilder
) -> (String, Array[String], Int, Int) {
  out.write_string(line)
  out.write_char('\n')
  (line, fields, 0, nr)
}

fn awk_is_zero_literal_expr_ast(expr_ast : AwkExprAst) -> Bool {
  match expr_ast {
    Raw(text) => {
      let t = aj_trim(text)
      t.length() > 0 && awk_is_numeric_string(t) && awk_parse_number(t) == 0.0
    }
    _ => false
  }
}

fn awk_stringify_simple_expr_ast(expr_ast : AwkExprAst) -> String? {
  match expr_ast {
    Raw(text) => Some(aj_trim(text))
    Concat(parts) => {
      let out = StringBuilder::new()
      let mut wrote = false
      for part in parts {
        match part {
          Raw(text) => {
            let token = aj_trim(text)
            if token.length() == 0 {
              continue
            }
            if wrote {
              out.write_char(' ')
            }
            out.write_string(token)
            wrote = true
          }
          _ => return None
        }
      }
      Some(out.to_string())
    }
    _ => None
  }
}

fn awk_getline_target_from_condition_ast(cond_ast : AwkExprAst) -> String? {
  match cond_ast {
    Binary(op, left, right) => {
      if op != ">" || not(awk_is_zero_literal_expr_ast(right)) {
        return None
      }
      match awk_stringify_simple_expr_ast(left) {
        Some(left_text) => {
          let expr = awk_strip_outer_parens(aj_trim(left_text))
          if expr == "getline" {
            Some("")
          } else if aj_starts_with(expr, "getline ") {
            Some(aj_trim(aj_substr(expr, 7, expr.length())))
          } else {
            None
          }
        }
        None => None
      }
    }
    _ => None
  }
}

fn awk_execute_action_ast_list(
  ctx : CommandContext,
  statements : Array[AwkStmt],
  lines : Array[String],
  line_idx : Int,
  line : String,
  fields : Array[String],
  nr : Int,
  fs : String,
  filename : String,
  vars : Map[String, String],
  array_vars : Map[String, String],
  out : StringBuilder
) -> (String, Array[String], Int, Int) {
  let mut current_line = line
  let mut current_fields = fields
  let mut current_nr = nr
  let mut consumed = 0

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
              awk_eval_expr_ast(
                expr_ast,
                current_line,
                current_fields,
                current_nr,
                current_fields.length(),
                vars,
                array_vars,
              ),
            ).to_int()
          None => 0
        }
        vars[awk_ctrl_exit_key] = code.to_string()
        break
      }
      Return(value_ast) => {
        let value = match value_ast {
          Some(expr_ast) =>
            awk_eval_expr_ast(
              expr_ast,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
          None => ""
        }
        vars[awk_ctrl_return_key] = "1"
        vars[awk_ctrl_return_value_key] = value
        break
      }
      PipeGetline(cmd_ast, target) => {
        let command = awk_eval_expr_ast(
          cmd_ast,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let line_from_cmd = awk_eval_getline_command_line(command)
        if target.length() == 0 {
          current_line = line_from_cmd
          let current_fs = awk_current_fs(fs, vars)
          current_fields = awk_split_fields(current_line, current_fs)
          vars["NF"] = current_fields.length().to_string()
        } else if awk_is_identifier(target) {
          vars[target] = line_from_cmd
        }
      }
      Getline(tail) => {
        let read_from_file_idx = awk_find_top_level_token(tail, "<")
        if read_from_file_idx > 0 {
          let target = aj_trim(aj_substr(tail, 0, read_from_file_idx))
          let path_expr = aj_trim(aj_substr(tail, read_from_file_idx + 1, tail.length()))
          let path = awk_eval_expr(
            path_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          let resolved = try {
            @fs.resolve_path(ctx.cwd, path)
          } catch {
            @fs.FsError(_) => ""
          }
          if resolved.length() > 0 {
            let content = try {
              ctx.fs.read_file(resolved)
            } catch {
              @fs.FsError(_) => ""
            }
            let first_line = aj_first_line(content)
            if target.length() == 0 {
              current_line = first_line
              let current_fs = awk_current_fs(fs, vars)
              current_fields = awk_split_fields(current_line, current_fs)
              vars["NF"] = current_fields.length().to_string()
            } else if awk_is_identifier(target) {
              vars[target] = first_line
            }
          }
          continue
        }

        // Keep parity with current awk-spec skip assumptions:
        // bare getline from BEGIN block stdin is still treated as unsupported.
        if line_idx < 0 && tail.length() == 0 {
          continue
        }

        let next_idx = line_idx + consumed + 1
        if next_idx >= 0 && next_idx < lines.length() {
          consumed += 1
          let next_line = lines[next_idx]
          current_nr += 1
          vars["NR"] = current_nr.to_string()
          vars["FNR"] = current_nr.to_string()
          vars["FILENAME"] = filename
          if tail.length() == 0 {
            current_line = next_line
            let current_fs = awk_current_fs(fs, vars)
            current_fields = awk_split_fields(current_line, current_fs)
            vars["NF"] = current_fields.length().to_string()
          } else if awk_is_identifier(tail) {
            vars[tail] = next_line
          } else {
            current_line = next_line
            let current_fs = awk_current_fs(fs, vars)
            current_fields = awk_split_fields(current_line, current_fs)
            vars["NF"] = current_fields.length().to_string()
          }
        }
      }
      SystemStmt => {
        vars[awk_ctrl_error_key] = "system() is not supported"
        vars[awk_ctrl_exit_key] = "1"
        break
      }
      SubstituteStmt(is_gsub, args) => {
        if args.length() >= 2 {
          let pattern = awk_eval_sub_pattern(
            args[0],
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          let replacement = awk_eval_expr(
            args[1],
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          let mut target_expr : String? = None
          if args.length() >= 3 {
            target_expr = Some(aj_trim(args[2]))
          }
          let source = match target_expr {
            Some(expr) => awk_eval_expr(
              expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            None => current_line
          }
          let (updated, _count) = if is_gsub {
            awk_replace_all_literal(source, pattern, replacement)
          } else {
            awk_replace_first_literal(source, pattern, replacement)
          }
          match target_expr {
            Some(expr) => {
              if awk_is_identifier(expr) {
                vars[expr] = updated
              } else {
                match awk_parse_array_ref(expr) {
                  Some((arr_name, idx_expr)) => {
                    let idx = awk_eval_expr(
                      idx_expr,
                      current_line,
                      current_fields,
                      current_nr,
                      current_fields.length(),
                      vars,
                      array_vars,
                    )
                    array_vars[awk_array_key(arr_name, idx)] = updated
                  }
                  None => ()
                }
              }
            }
            None => {
              current_line = updated
              let current_fs = awk_current_fs(fs, vars)
              current_fields = awk_split_fields(current_line, current_fs)
              vars["NF"] = current_fields.length().to_string()
            }
          }
        }
      }
      ExprStmt(expr_ast) => {
        ignore(
          awk_eval_expr_ast(
            expr_ast,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          ),
        )
      }
      CompoundAssignStmt(lhs, op, rhs_ast) => {
        let right = awk_parse_number(
          awk_eval_expr_ast(
            rhs_ast,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          ),
        )
        if awk_is_identifier(lhs) {
          let left = awk_parse_number(vars.get(lhs).unwrap_or(""))
          let value = match op {
            "+=" => left + right
            "-=" => left - right
            "*=" => left * right
            "/=" => if right == 0.0 { 0.0 } else { left / right }
            _ => left
          }
          vars[lhs] = awk_number_to_string(value)
        } else {
          match awk_parse_array_ref(lhs) {
            Some((arr_name, idx_expr)) => {
              let idx = awk_eval_expr(
                idx_expr,
                current_line,
                current_fields,
                current_nr,
                current_fields.length(),
                vars,
                array_vars,
              )
              let key = awk_array_key(arr_name, idx)
              let left = awk_parse_number(array_vars.get(key).unwrap_or(""))
              let value = match op {
                "+=" => left + right
                "-=" => left - right
                "*=" => left * right
                "/=" => if right == 0.0 { 0.0 } else { left / right }
                _ => left
              }
              array_vars[key] = awk_number_to_string(value)
            }
            None => ()
          }
        }
      }
      AssignStmt(lhs, rhs_ast) => {
        let value = awk_eval_expr_ast(
          rhs_ast,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        if awk_is_identifier(lhs) {
          vars[lhs] = value
        } else {
          match awk_parse_array_ref(lhs) {
            Some((arr_name, idx_expr)) => {
              let idx = awk_eval_expr(
                idx_expr,
                current_line,
                current_fields,
                current_nr,
                current_fields.length(),
                vars,
                array_vars,
              )
              array_vars[awk_array_key(arr_name, idx)] = value
            }
            None => ()
          }
        }
      }
      FieldAssignStmt(lhs, rhs_ast) => {
        let value = awk_eval_expr_ast(
          rhs_ast,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        if lhs == "$0" {
          current_line = value
          let current_fs = awk_current_fs(fs, vars)
          current_fields = awk_split_fields(current_line, current_fs)
          vars["NF"] = current_fields.length().to_string()
        } else {
          let field_idx = aj_parse_int(aj_substr(lhs, 1, lhs.length()))
          if field_idx == 0 {
            current_line = value
            let current_fs = awk_current_fs(fs, vars)
            current_fields = awk_split_fields(current_line, current_fs)
            vars["NF"] = current_fields.length().to_string()
          } else if field_idx > 0 {
            while current_fields.length() < field_idx {
              current_fields.push("")
            }
            current_fields[field_idx - 1] = value
            let ofs = vars.get("OFS").unwrap_or(" ")
            current_line = awk_join_fields(current_fields, ofs)
            vars["NF"] = current_fields.length().to_string()
          }
        }
      }
      Delete(target_expr) => {
        match awk_parse_array_ref(target_expr) {
          Some((arr_name, idx_expr)) => {
            let idx = awk_eval_expr(
              idx_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            array_vars.remove(awk_array_key(arr_name, idx))
          }
          None => ()
        }
      }
      Printf(rest) => {
        let (printf_expr, target_expr, append) = match awk_parse_print_redirection(rest) {
          Some(parsed) => parsed
          None => (rest, "", false)
        }
        let (fmt_expr, arg_exprs) = awk_parse_printf("printf " + printf_expr)
        let fmt_value = awk_eval_expr(
          fmt_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let fmt_args : Array[String] = []
        for expr in arg_exprs {
          fmt_args.push(
            awk_eval_expr(
              expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            ),
          )
        }
        let payload = awk_format_printf(fmt_value, fmt_args)
        if target_expr.length() == 0 {
          out.write_string(payload)
        } else {
          let target = awk_eval_expr(
            target_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
          let resolved = try {
            @fs.resolve_path(ctx.cwd, target)
          } catch {
            @fs.FsError(msg) => {
              vars[awk_ctrl_error_key] = msg
              vars[awk_ctrl_exit_key] = "1"
              break
            }
          }
          let existing = if append {
            try {
              ctx.fs.read_file(resolved)
            } catch {
              @fs.FsError(_) => ""
            }
          } else {
            ""
          }
          try {
            ctx.fs.write_file(resolved, existing + payload)
          } catch {
            @fs.FsError(msg) => {
              vars[awk_ctrl_error_key] = msg
              vars[awk_ctrl_exit_key] = "1"
              break
            }
          }
        }
      }
      Print(rest) => {
        if awk_find_top_level_token(rest, "|") >= 0 {
          vars[awk_ctrl_error_key] = "piping to external commands is not supported"
          vars[awk_ctrl_exit_key] = "1"
          break
        }
        match awk_parse_print_redirection(rest) {
          Some((value_expr, target_expr, append)) => {
            let payload = awk_render_print_output(
              value_expr,
              current_line,
              current_fields,
              current_nr,
              vars,
              array_vars,
            )
            let target = awk_eval_expr(
              target_expr,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            )
            let resolved = try {
              @fs.resolve_path(ctx.cwd, target)
            } catch {
              @fs.FsError(msg) => {
                vars[awk_ctrl_error_key] = msg
                vars[awk_ctrl_exit_key] = "1"
                break
              }
            }
            let existing = if append {
              try {
                ctx.fs.read_file(resolved)
              } catch {
                @fs.FsError(_) => ""
              }
            } else {
              ""
            }
            try {
              ctx.fs.write_file(resolved, existing + payload)
            } catch {
              @fs.FsError(msg) => {
                vars[awk_ctrl_error_key] = msg
                vars[awk_ctrl_exit_key] = "1"
                break
              }
            }
          }
          None => {
            out.write_string(
              awk_render_print_output(
                rest,
                current_line,
                current_fields,
                current_nr,
                vars,
                array_vars,
              ),
            )
          }
        }
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
            let (next_line, next_fields, consumed_body, new_nr) = awk_execute_action_ast_list(
              ctx,
              body_stmts,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
            current_line = next_line
            current_fields = next_fields
            consumed += consumed_body
            current_nr = new_nr
          }
        }
      }
      For(init_stmts, cond_ast, update_stmts, body_stmts) => {
        if init_stmts.length() > 0 {
          let (next_line, next_fields, consumed_init, new_nr) = awk_execute_action_ast_list(
            ctx,
            init_stmts,
            lines,
            line_idx + consumed,
            current_line,
            current_fields,
            current_nr,
            fs,
            filename,
            vars,
            array_vars,
            out,
          )
          current_line = next_line
          current_fields = next_fields
          consumed += consumed_init
          current_nr = new_nr
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
                  current_line,
                  current_fields,
                  current_nr,
                  current_fields.length(),
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
            let (next_line, next_fields, consumed_body, new_nr) = awk_execute_action_ast_list(
              ctx,
              body_stmts,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
            current_line = next_line
            current_fields = next_fields
            consumed += consumed_body
            current_nr = new_nr
          }

          if vars.contains(awk_ctrl_exit_key) ||
            vars.contains(awk_ctrl_next_key) ||
            vars.contains(awk_ctrl_return_key) {
            break
          }

          if update_stmts.length() > 0 {
            let (next_line, next_fields, consumed_update, new_nr) = awk_execute_action_ast_list(
              ctx,
              update_stmts,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
            current_line = next_line
            current_fields = next_fields
            consumed += consumed_update
            current_nr = new_nr
          }

          loop_count += 1
          if loop_count > awk_loop_guard_limit {
            break
          }
        }
      }
      If(cond_ast, then_stmts, else_stmts) => {
        let mut cond_passed = false
        let mut handled_getline = false
        match awk_getline_target_from_condition_ast(cond_ast) {
          Some(target) => {
            handled_getline = true
            let next_idx = line_idx + consumed + 1
            if next_idx >= 0 && next_idx < lines.length() {
              let next_line = lines[next_idx]
              consumed += 1
              current_nr += 1
              vars["NR"] = current_nr.to_string()
              vars["FNR"] = current_nr.to_string()
              if awk_is_identifier(target) {
                vars[target] = next_line
              } else {
                current_line = next_line
                let current_fs = awk_current_fs(fs, vars)
                current_fields = awk_split_fields(current_line, current_fs)
                vars["NF"] = current_fields.length().to_string()
              }
              cond_passed = true
            } else {
              cond_passed = false
            }
          }
          None => ()
        }
        if not(handled_getline) {
          cond_passed = awk_eval_condition_ast(
            cond_ast,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        }
        if cond_passed {
          let (next_line, next_fields, consumed_if, new_nr) = if then_stmts.length() == 0 {
            // Keep historical behavior for empty if-body branches.
            awk_execute_empty_action_branch(current_line, current_fields, current_nr, out)
          } else {
            awk_execute_action_ast_list(
              ctx,
              then_stmts,
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
          }
          current_line = next_line
          current_fields = next_fields
          consumed += consumed_if
          current_nr = new_nr
        } else {
          match else_stmts {
            Some(else_branch) => {
              let (next_line, next_fields, consumed_if, new_nr) = if else_branch.length() == 0 {
                // Keep historical behavior for explicit else {}.
                awk_execute_empty_action_branch(current_line, current_fields, current_nr, out)
              } else {
                awk_execute_action_ast_list(
                  ctx,
                  else_branch,
                  lines,
                  line_idx + consumed,
                  current_line,
                  current_fields,
                  current_nr,
                  fs,
                  filename,
                  vars,
                  array_vars,
                  out,
                )
              }
              current_line = next_line
              current_fields = next_fields
              consumed += consumed_if
              current_nr = new_nr
            }
            None => ()
          }
        }
      }
      Simple(_raw_stmt) => ()
    }
  }

  (current_line, current_fields, consumed, current_nr)
}
