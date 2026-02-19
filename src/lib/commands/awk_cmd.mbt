// moon_bash Commands - awk command entry point (cmd_awk)

fn cmd_awk(ctx : CommandContext) -> @ast.ExecResult {
  let mut fs = " "
  let mut program : String? = None
  let files : Array[String] = []
  let initial_vars : Array[(String, String)] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-v" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("awk: option -v requires an argument\n")
      }
      match awk_parse_var_assignment(ctx.args[i + 1]) {
        Some((name, value)) => initial_vars.push((name, value))
        None => return @ast.ExecResult::err("awk: invalid -v assignment: \{ctx.args[i + 1]}\n")
      }
      i += 2
      continue
    }
    if aj_starts_with(arg, "-v") && arg.length() > 2 {
      let spec = aj_substr(arg, 2, arg.length())
      match awk_parse_var_assignment(spec) {
        Some((name, value)) => initial_vars.push((name, value))
        None => return @ast.ExecResult::err("awk: invalid -v assignment: \{spec}\n")
      }
      i += 1
      continue
    }
    if arg == "-F" && i + 1 < ctx.args.length() {
      fs = ctx.args[i + 1]
      i += 2
      continue
    }
    if aj_starts_with(arg, "-F") && arg.length() > 2 {
      fs = aj_substr(arg, 2, arg.length())
      i += 1
      continue
    }
    if program is None {
      program = Some(arg)
    } else {
      files.push(arg)
    }
    i += 1
  }

  if fs == "\\t" {
    fs = "\t"
  }

  let prog_src = match program {
    Some(p) => p
    None => return @ast.ExecResult::err("awk: missing program\n")
  }
  let normalized_prog_src = awk_strip_comments(prog_src)
  // Guard against parser artifacts where shell fragments are accidentally
  // appended to awk source (e.g. newline followed by `' x=1 ...`).
  if aj_find_substring(normalized_prog_src, "\n'") >= 0 ||
    aj_find_substring(normalized_prog_src, "\r'") >= 0 {
    return @ast.ExecResult::err("awk: syntax error\n")
  }
  let (program_without_functions, functions) = awk_extract_functions(normalized_prog_src)
  let prog = awk_parse_program(program_without_functions)

  let (input, filename) = if files.length() > 0 {
    let path = files[0]
    if path == "-" {
      (ctx.stdin_content, "-")
    } else if path == "/dev/null" {
      ("", "/dev/null")
    } else {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, path)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
      }
      let content = try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("awk: \{msg}\n")
      }
      (content, path)
    }
  } else {
    (ctx.stdin_content, "-")
  }

  let out = StringBuilder::new()
  let vars : Map[String, String] = {}
  let array_vars : Map[String, String] = {}
  let lines = aj_split_lines_records(input)
  let mut nr = 0
  vars["FS"] = fs
  vars["FILENAME"] = filename
  vars["NR"] = "0"
  vars["FNR"] = "0"
  vars["NF"] = "0"
  vars["RSTART"] = "0"
  vars["RLENGTH"] = "-1"
  awk_install_functions(vars, functions)
  for pair in initial_vars {
    vars[pair.0] = pair.1
  }

  for action in prog.begin_actions {
    if vars.contains(awk_ctrl_exit_key) {
      break
    }
      let (_, _, _, new_nr) = awk_execute_action(
        ctx,
        action,
        lines,
        -1,
        "",
        [],
        nr,
        0,
        fs,
        filename,
        vars,
        array_vars,
        out,
      )
      nr = new_nr
  }

  let mut line_idx = 0
  let mut in_range = false
  while line_idx < lines.length() {
    if vars.contains(awk_ctrl_exit_key) {
      break
    }
    let line = lines[line_idx]
    nr += 1
    vars["NR"] = nr.to_string()
    vars["FNR"] = nr.to_string()
    vars["FILENAME"] = filename
    let current_fs = awk_current_fs(fs, vars)
    let fields = awk_split_fields(line, current_fs)
    let nf = fields.length()
    vars["NF"] = nf.to_string()
    vars.remove(awk_ctrl_next_key)
    let (matched, next_range) = awk_pattern_match_program(
      prog,
      line,
      fields,
      nr,
      nf,
      vars,
      array_vars,
      in_range,
    )
    in_range = next_range
    if matched {
      let (_, _, consumed, new_nr) = awk_execute_action(
        ctx,
        prog.action,
        lines,
        line_idx,
        line,
        fields,
        nr,
        nf,
        fs,
        filename,
        vars,
        array_vars,
        out,
      )
      nr = new_nr
      vars["NR"] = nr.to_string()
      vars["FNR"] = nr.to_string()
      vars.remove(awk_ctrl_next_key)
      line_idx += consumed + 1
    } else {
      line_idx += 1
    }
  }

  let begin_exit = vars.get(awk_ctrl_exit_key)
  match begin_exit {
    Some(_) => vars.remove(awk_ctrl_exit_key)
    None => ()
  }

  if not(vars.contains(awk_ctrl_error_key)) {
    for action in prog.end_actions {
      if vars.contains(awk_ctrl_exit_key) {
        break
      }
        let end_idx = if lines.length() > 0 { lines.length() - 1 } else { -1 }
        let (_, _, _, _) = awk_execute_action(
          ctx,
          action,
          lines,
          end_idx,
          "",
          [],
          nr,
          0,
          fs,
          filename,
          vars,
          array_vars,
          out,
        )
    }
  }

  if not(vars.contains(awk_ctrl_exit_key)) {
    match begin_exit {
      Some(code) => vars[awk_ctrl_exit_key] = code
      None => ()
    }
  }

  let exit_code = match vars.get(awk_ctrl_exit_key) {
    Some(code) => aj_parse_int(code)
    None => 0
  }
  let stderr = match vars.get(awk_ctrl_error_key) {
    Some(msg) => "awk: \{msg}\n"
    None => ""
  }
  @ast.ExecResult::new(stdout=out.to_string(), stderr=stderr, exit_code=exit_code)
}
