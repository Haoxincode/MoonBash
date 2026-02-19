// moon_bash Commands - jq command entry point (cmd_jq)

fn cmd_jq(ctx : CommandContext) -> @ast.ExecResult {
  let mut compact = false
  let mut raw = false
  let mut null_input = false
  let mut slurp = false

  let mut filter : String? = None
  let mut input_file : String? = None

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if aj_starts_with(arg, "-") && filter is None {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'c' => compact = true
          'r' => raw = true
          'n' => null_input = true
          's' => slurp = true
          _ => ()
        }
      }
      i += 1
      continue
    }
    if filter is None {
      filter = Some(arg)
    } else if input_file is None {
      input_file = Some(arg)
    }
    i += 1
  }

  let jq_filter = match filter {
    Some(f) => f
    None => return @ast.ExecResult::err("jq: missing filter\n")
  }

  let (query_opt, parse_err) = jq_parse_query_with_compat(jq_filter)

  let inputs : Array[Json] = if null_input {
    [Json::null()]
  } else {
    let raw_source = match input_file {
      Some(path) => {
        let resolved = try {
          @fs.resolve_path(ctx.cwd, path)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("jq: \{msg}\n")
        }
        try {
          ctx.fs.read_file(resolved)
        } catch {
          @fs.FsError(msg) => return @ast.ExecResult::err("jq: \{msg}\n")
        }
      }
      None => ctx.stdin_content
    }
    let source = jq_strip_bom(raw_source)
    let trimmed = aj_trim(source)
    if slurp {
      if trimmed.length() == 0 {
        [Json::array([])]
      } else {
        let single = try {
          Some(@json.parse(trimmed[:]))
        } catch {
          _ => None
        }
        match single {
          Some(value) => [Json::array([value])]
          None => {
            let lines = aj_split_lines_records(source)
            let arr : Array[Json] = []
            for line in lines {
              let t = aj_trim(line)
              if t.length() == 0 {
                continue
              }
              let parsed = try {
                @json.parse(t[:])
              } catch {
                _ => return @ast.ExecResult::err("jq: invalid JSON input\n")
              }
              arr.push(parsed)
            }
            [Json::array(arr)]
          }
        }
      }
    } else {
      if trimmed.length() == 0 {
        [Json::null()]
      } else {
        let single = try {
          Some(@json.parse(trimmed[:]))
        } catch {
          _ => None
        }
        match single {
          Some(value) => [value]
          None => {
            let lines = aj_split_lines_records(source)
            let parsed_lines : Array[Json] = []
            for line in lines {
              let t = aj_trim(line)
              if t.length() == 0 {
                continue
              }
              let parsed = try {
                @json.parse(t[:])
              } catch {
                _ => return @ast.ExecResult::err("jq: invalid JSON input\n")
              }
              parsed_lines.push(parsed)
            }
            if parsed_lines.length() == 0 { [Json::null()] } else { parsed_lines }
          }
        }
      }
    }
  }

  if jq_repeat_result_too_long(jq_filter, inputs) {
    return @ast.ExecResult::err("jq: EvalError(\"Repeat string result too long\")\n")
  }

  if query_opt is None {
    let out = StringBuilder::new()
    for input in inputs {
      match jq_manual_compat_values(jq_filter, input) {
        Some(values) => {
          for value in values {
            if raw {
              match value {
                Json::String(s) => out.write_string(s)
                _ => out.write_string(value.stringify(indent=if compact { 0 } else { 2 }))
              }
            } else {
              out.write_string(value.stringify(indent=if compact { 0 } else { 2 }))
            }
            out.write_char('\n')
          }
        }
        None => return @ast.ExecResult::err(parse_err)
      }
    }
    return @ast.ExecResult::ok(out.to_string())
  }

  let query = match query_opt {
    Some(q) => q
    None => return @ast.ExecResult::err(parse_err)
  }

  let out = StringBuilder::new()
  for input in inputs {
    let values = match jq_manual_compat_values(jq_filter, input) {
      Some(values) => values
      None => {
        try {
          @moonjq.run_json(query, input)
        } catch {
          e => {
            match jq_manual_compat_values(jq_filter, input) {
              Some(values) => values
              None => return @ast.ExecResult::err("jq: \{e}\n")
            }
          }
        }
      }
    }
    for value in values {
      if raw {
        match value {
          Json::String(s) => out.write_string(s)
          _ => out.write_string(value.stringify(indent=if compact { 0 } else { 2 }))
        }
      } else {
        out.write_string(value.stringify(indent=if compact { 0 } else { 2 }))
      }
      out.write_char('\n')
    }
  }
  @ast.ExecResult::ok(out.to_string())
}
