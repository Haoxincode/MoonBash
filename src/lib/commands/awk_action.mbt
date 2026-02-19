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
      For(init_stmts, cond_expr, update_stmts, body_stmts) => {
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
          if cond_expr.length() > 0 &&
            not(
              awk_eval_condition(
                cond_expr,
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
      If(cond_expr, then_stmts, else_stmts) => {
        let mut cond_passed = false
        let cond_text = awk_strip_outer_parens(cond_expr)
        let gt_idx = awk_find_top_level_token(cond_text, ">")
        let mut handled_getline = false
        if gt_idx > 0 {
          let left_expr = awk_strip_outer_parens(aj_trim(aj_substr(cond_text, 0, gt_idx)))
          let right_expr = aj_trim(aj_substr(cond_text, gt_idx + 1, cond_text.length()))
          if right_expr == "0" && (left_expr == "getline" || aj_starts_with(left_expr, "getline ")) {
            handled_getline = true
            let target = if left_expr.length() > 7 {
              aj_trim(aj_substr(left_expr, 7, left_expr.length()))
            } else {
              ""
            }
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
        }
        if not(handled_getline) {
          cond_passed = awk_eval_condition(
            cond_expr,
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
            awk_execute_action_simple(
              ctx,
              "",
              lines,
              line_idx + consumed,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              fs,
              filename,
              vars,
              array_vars,
              out,
            )
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
                awk_execute_action_simple(
                  ctx,
                  "",
                  lines,
                  line_idx + consumed,
                  current_line,
                  current_fields,
                  current_nr,
                  current_fields.length(),
                  fs,
                  filename,
                  vars,
                  array_vars,
                  out,
                )
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
      Simple(raw_stmt) => {
        let (next_line, next_fields, consumed_stmt, new_nr) = awk_execute_action_simple(
          ctx,
          raw_stmt,
          lines,
          line_idx + consumed,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          fs,
          filename,
          vars,
          array_vars,
          out,
        )
        current_line = next_line
        current_fields = next_fields
        consumed += consumed_stmt
        current_nr = new_nr
      }
    }
  }

  (current_line, current_fields, consumed, current_nr)
}

fn awk_execute_action_simple(
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
  let mut current_line = line
  let mut current_fields = fields
  let mut current_nr = nr
  let mut consumed = 0

  if act.length() == 0 {
    out.write_string(current_line)
    out.write_char('\n')
    return (current_line, current_fields, consumed, current_nr)
  }

  let statements = awk_merge_if_else_statements(awk_split_statements(act))
  for stmt_raw in statements {
    if vars.contains(awk_ctrl_exit_key) ||
      vars.contains(awk_ctrl_next_key) ||
      vars.contains(awk_ctrl_return_key) {
      break
    }
    let stmt = aj_trim(stmt_raw)
    if stmt.length() == 0 {
      continue
    }

    if stmt == "next" {
      vars[awk_ctrl_next_key] = "1"
      break
    }

    if stmt == "exit" || aj_starts_with(stmt, "exit ") || aj_starts_with(stmt, "exit(") {
      let code_expr = if stmt.length() > 4 {
        aj_trim(aj_substr(stmt, 4, stmt.length()))
      } else {
        ""
      }
      let code = if code_expr.length() == 0 {
        0
      } else {
        awk_eval_number(
          code_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        ).to_int()
      }
      vars[awk_ctrl_exit_key] = code.to_string()
      break
    }

    if stmt == "return" || aj_starts_with(stmt, "return ") || aj_starts_with(stmt, "return(") {
      let value_expr = if stmt.length() > 6 {
        aj_trim(aj_substr(stmt, 6, stmt.length()))
      } else {
        ""
      }
      let value = if value_expr.length() == 0 {
        ""
      } else {
        awk_eval_expr(
          value_expr,
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
      }
      vars[awk_ctrl_return_key] = "1"
      vars[awk_ctrl_return_value_key] = value
      break
    }

    if aj_starts_with(stmt, "system(") && aj_ends_with(stmt, ")") {
      vars[awk_ctrl_error_key] = "system() is not supported"
      vars[awk_ctrl_exit_key] = "1"
      break
    }

    let pipe_getline_idx = awk_find_top_level_token(stmt, "| getline")
    if pipe_getline_idx > 0 {
      let cmd_expr = aj_trim(aj_substr(stmt, 0, pipe_getline_idx))
      let target = aj_trim(aj_substr(stmt, pipe_getline_idx + 9, stmt.length()))
      let command = awk_eval_expr(
        cmd_expr,
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
      continue
    }

    if stmt == "getline" || aj_starts_with(stmt, "getline ") {
      let tail = if stmt.length() > 7 { aj_trim(aj_substr(stmt, 7, stmt.length())) } else { "" }
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
      continue
    }

    if aj_starts_with(stmt, "delete ") {
      let target = aj_trim(aj_substr(stmt, 6, stmt.length()))
      match awk_parse_array_ref(target) {
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
      continue
    }

    let is_gsub = aj_starts_with(stmt, "gsub(") && aj_ends_with(stmt, ")")
    let is_sub = aj_starts_with(stmt, "sub(") && aj_ends_with(stmt, ")")
    if is_gsub || is_sub {
      let offset = if is_gsub { 5 } else { 4 }
      let inner = aj_substr(stmt, offset, stmt.length() - 1)
      let args = awk_split_csv_args(inner)
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
      continue
    }

    if aj_starts_with(stmt, "match(") && aj_ends_with(stmt, ")") {
      let inner = aj_substr(stmt, 6, stmt.length() - 1)
      let args = awk_split_csv_args(inner)
      if args.length() >= 2 {
        let source = awk_eval_expr(
          args[0],
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let pattern_expr = aj_trim(args[1])
        let pattern = if aj_starts_with(pattern_expr, "/") &&
          aj_ends_with(pattern_expr, "/") {
          pattern_expr
        } else {
          awk_eval_expr(
            pattern_expr,
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        }
        let (rstart, rlength) = awk_find_regex_match_range(pattern, source)
        vars["RSTART"] = rstart.to_string()
        vars["RLENGTH"] = rlength.to_string()
      }
      continue
    }

    if aj_starts_with(stmt, "split(") && aj_ends_with(stmt, ")") {
      let inner = aj_substr(stmt, 6, stmt.length() - 1)
      let args = awk_split_csv_args(inner)
      if args.length() >= 2 {
        let source = awk_eval_expr(
          args[0],
          current_line,
          current_fields,
          current_nr,
          current_fields.length(),
          vars,
          array_vars,
        )
        let arr_name = aj_trim(args[1])
        let delim = if args.length() >= 3 {
          awk_eval_split_delim(
            args[2],
            current_line,
            current_fields,
            current_nr,
            current_fields.length(),
            vars,
            array_vars,
          )
        } else {
          awk_current_fs(fs, vars)
        }
        let pieces = awk_split_for_split_builtin(source, delim)
        for j = 0; j < pieces.length(); j = j + 1 {
          array_vars[awk_array_key(arr_name, (j + 1).to_string())] = pieces[j]
        }
        vars[arr_name] = pieces.length().to_string()
      }
      continue
    }

    if aj_starts_with(stmt, "printf") {
      let rest = aj_trim(aj_substr(stmt, 6, stmt.length()))
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
      continue
    }

    if aj_starts_with(stmt, "print") {
      let rest = aj_trim(aj_substr(stmt, 5, stmt.length()))
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
      continue
    }

    match awk_parse_call_expr(stmt) {
      Some((call_name, args)) => {
        if call_name == "close" {
          continue
        }
        if call_name == "sprintf" {
          ignore(
            awk_eval_expr(
              stmt,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
            ),
          )
          continue
        }
        match awk_get_function(vars, call_name) {
          Some(_) => {
            ignore(awk_eval_user_function(
              call_name,
              args,
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
              vars,
              array_vars,
              out,
            ))
            continue
          }
          None => ()
        }
      }
      None => ()
    }

    if aj_ends_with(stmt, "++") {
      let name = aj_trim(aj_substr(stmt, 0, stmt.length() - 2))
      if awk_is_identifier(name) {
        let value = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(value + 1.0)
      } else {
        match awk_parse_array_ref(name) {
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
            let value = awk_parse_number(array_vars.get(key).unwrap_or(""))
            array_vars[key] = awk_number_to_string(value + 1.0)
          }
          None => ()
        }
      }
      continue
    }

    let plus_eq_idx = awk_find_top_level_token(stmt, "+=")
    if plus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, plus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, plus_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
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
              current_line,
              current_fields,
              current_nr,
              current_fields.length(),
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

    let minus_eq_idx = awk_find_top_level_token(stmt, "-=")
    if minus_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, minus_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, minus_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(left - right)
      } else {
        match awk_parse_array_ref(name) {
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
            array_vars[key] = awk_number_to_string(left - right)
          }
          None => ()
        }
      }
      continue
    }

    let mul_eq_idx = awk_find_top_level_token(stmt, "*=")
    if mul_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, mul_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, mul_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        vars[name] = awk_number_to_string(left * right)
      } else {
        match awk_parse_array_ref(name) {
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
            array_vars[key] = awk_number_to_string(left * right)
          }
          None => ()
        }
      }
      continue
    }

    let div_eq_idx = awk_find_top_level_token(stmt, "/=")
    if div_eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, div_eq_idx))
      let rhs = aj_trim(aj_substr(stmt, div_eq_idx + 2, stmt.length()))
      let right = awk_eval_number(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        let left = awk_parse_number(vars.get(name).unwrap_or(""))
        let value = if right == 0.0 { 0.0 } else { left / right }
        vars[name] = awk_number_to_string(value)
      } else {
        match awk_parse_array_ref(name) {
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
            let value = if right == 0.0 { 0.0 } else { left / right }
            array_vars[key] = awk_number_to_string(value)
          }
          None => ()
        }
      }
      continue
    }

    let eq_idx = awk_find_top_level_token(stmt, "=")
    if eq_idx > 0 {
      let name = aj_trim(aj_substr(stmt, 0, eq_idx))
      let rhs = aj_trim(aj_substr(stmt, eq_idx + 1, stmt.length()))
      let value = awk_eval_expr(
        rhs,
        current_line,
        current_fields,
        current_nr,
        current_fields.length(),
        vars,
        array_vars,
      )
      if awk_is_identifier(name) {
        vars[name] = value
      } else if name == "$0" {
        current_line = value
        let current_fs = awk_current_fs(fs, vars)
        current_fields = awk_split_fields(current_line, current_fs)
        vars["NF"] = current_fields.length().to_string()
      } else if aj_starts_with(name, "$") {
        let field_idx = aj_parse_int(aj_substr(name, 1, name.length()))
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
      } else {
        match awk_parse_array_ref(name) {
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
      continue
    }
  }

  (current_line, current_fields, consumed, current_nr)
}
