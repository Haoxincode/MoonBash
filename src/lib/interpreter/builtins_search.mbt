// moon_bash Interpreter - Search Builtins
// Split from builtins_extra.mbt for maintainability.

fn ExecContext::builtin_sed(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  for arg in args {
    if trim_ascii_space(arg) == "..." {
      self.stderr_buf.write_string("sed: invalid script\n")
      self.exit_code = 1
      return
    }
  }

  let expressions : Array[String] = []
  let files : Array[String] = []
  let mut script_taken = false
  let mut inplace = false
  let mut extended = false
  let mut quiet = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-i" || (arg.has_prefix("-i") && arg.length() > 1 && not(script_taken)) {
      inplace = true
    } else if arg == "-n" {
      quiet = true
    } else if arg == "-E" || arg == "-r" {
      extended = true
    } else if arg.length() > 2 && arg[0] == '-' && not(script_taken) {
      let mut handled_bundle = true
      let mut treat_as_script = false
      let mut j = 1
      while j < arg.length() {
        let flag = arg[j].to_int().unsafe_to_char()
        if flag == 'n' {
          quiet = true
          j += 1
        } else if flag == 'E' || flag == 'r' {
          extended = true
          j += 1
        } else if flag == 'i' {
          inplace = true
          j += 1
        } else if flag == 'e' {
          if j + 1 < arg.length() {
            expressions.push(arg.substring(start=j + 1))
          } else if i + 1 < args.length() {
            i += 1
            expressions.push(args[i])
          } else {
            self.stderr_buf.write_string("sed: option requires an argument -- e\n")
            self.exit_code = 1
            return
          }
          script_taken = true
          break
        } else {
          handled_bundle = false
          treat_as_script = true
          break
        }
      }
      if treat_as_script {
        let mut candidate = arg
        let mut consumed = 0
        let mut parsed = parse_sed_script_commands(candidate, extended~)
        while parsed is None && i + consumed + 1 < args.length() {
          consumed += 1
          candidate = candidate + " " + args[i + consumed]
          parsed = parse_sed_script_commands(candidate, extended~)
        }
        if parsed is Some(_) {
          expressions.push(candidate)
          i += consumed
        } else {
          expressions.push(arg)
        }
        script_taken = true
      } else if not(handled_bundle) {
        // Unknown non-bundled option form; defer to script handling fallback.
        let mut candidate = arg
        let mut consumed = 0
        let mut parsed = parse_sed_script_commands(candidate, extended~)
        while parsed is None && i + consumed + 1 < args.length() {
          consumed += 1
          candidate = candidate + " " + args[i + consumed]
          parsed = parse_sed_script_commands(candidate, extended~)
        }
        if parsed is Some(_) {
          expressions.push(candidate)
          i += consumed
        } else {
          expressions.push(arg)
        }
        script_taken = true
      }
    } else if arg == "-e" && i + 1 < args.length() {
      i += 1
      expressions.push(args[i])
      script_taken = true
    } else if arg.has_prefix("-e") && arg.length() > 2 {
      expressions.push(arg.substring(start=2))
      script_taken = true
    } else if not(script_taken) {
      let mut candidate = arg
      let mut consumed = 0
      let mut parsed = parse_sed_script_commands(candidate, extended~)
      while parsed is None && i + consumed + 1 < args.length() {
        consumed += 1
        candidate = candidate + " " + args[i + consumed]
        parsed = parse_sed_script_commands(candidate, extended~)
      }
      if parsed is Some(_) {
        expressions.push(candidate)
        i += consumed
      } else {
        expressions.push(arg)
      }
      script_taken = true
    } else {
      files.push(arg)
    }
    i += 1
  }

  if expressions.length() == 0 {
    self.stderr_buf.write_string("sed: missing script\n")
    self.exit_code = 1
    return
  }

  for expr in expressions {
    match parse_sed_inline_directives(expr) {
      Some((quiet_directive, extended_directive)) => {
        if quiet_directive {
          quiet = true
        }
        if extended_directive {
          extended = true
        }
      }
      None => ()
    }
  }

  let script_builder = StringBuilder::new()
  for idx = 0; idx < expressions.length(); idx = idx + 1 {
    let normalized_expr = trim_ascii_left(expressions[idx])
    if normalized_expr == "..." {
      self.stderr_buf.write_string("sed: invalid script\n")
      self.exit_code = 1
      return
    }
    if idx > 0 {
      script_builder.write_char('\n')
    }
    script_builder.write_string(expressions[idx])
  }
  let script = script_builder.to_string()
  let commands = match parse_sed_script_commands(script, extended~) {
    Some(cmds) => cmds
    None => {
      self.stderr_buf.write_string("sed: invalid script\n")
      self.exit_code = 1
      return
    }
  }
  match sed_find_missing_branch_label(commands) {
    Some(name) => {
      self.stderr_buf.write_string("sed: can't find label \{name}\n")
      self.exit_code = 1
      return
    }
    None => ()
  }

  if inplace && files.length() == 0 {
    self.stderr_buf.write_string("sed: no input files\n")
    self.exit_code = 1
    return
  }

  let inputs : Array[String] = []
  let input_paths : Array[String] = []
  if files.length() == 0 {
    inputs.push(self.stdin_buf)
    input_paths.push("")
  } else {
    let mut stdin_used = false
    for path in files {
      if path == "-" {
        if stdin_used {
          inputs.push("")
        } else {
          inputs.push(self.stdin_buf)
          stdin_used = true
        }
        input_paths.push("")
        continue
      }
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      let content = try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("sed: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
      inputs.push(content)
      input_paths.push(resolved)
    }
  }

  if inplace {
    for idx = 0; idx < inputs.length(); idx = idx + 1 {
      let (rendered, _) = self.sed_render_input(commands, inputs[idx], quiet~)
      if self.exit_code != 0 {
        return
      }
      if input_paths[idx].length() > 0 {
        try {
          self.fs.write_file(input_paths[idx], rendered)
        } catch {
          @fs.FsError(msg) => {
            self.stderr_buf.write_string("sed: \{msg}\n")
            self.exit_code = 1
            return
          }
        }
      }
    }
  } else {
    let merged_input = StringBuilder::new()
    let mut prev_missing_newline = false
    for idx = 0; idx < inputs.length(); idx = idx + 1 {
      let chunk = inputs[idx]
      if idx > 0 && prev_missing_newline && chunk.length() > 0 {
        merged_input.write_char('\n')
      }
      merged_input.write_string(chunk)
      prev_missing_newline = chunk.length() > 0 &&
        chunk[chunk.length() - 1].to_int().unsafe_to_char() != '\n'
    }
    let (rendered, _) = self.sed_render_input(commands, merged_input.to_string(), quiet~)
    if self.exit_code != 0 {
      return
    }
    self.stdout_buf.write_string(rendered)
  }

  self.exit_code = 0
}

fn ExecContext::sed_render_input(
  self : ExecContext,
  commands : Array[SedCommand],
  input : String,
  quiet~ : Bool = false
) -> (String, Bool) {
  let out = StringBuilder::new()
  let lines = sed_split_lines_with_flags(input)
  let total_lines = lines.length()
  let range_states = Array::makei(
    commands.length(),
    _ => ({ in_range: false, relative_end_line: -1, pending_single_line: false }),
  )
  let mut hold_space = ""
  let mut quit = false
  let mut pending_no_newline = false
  let mut executed_steps = 0
  let mut last_regex : @regex.GrepMatcher? = None

  let label_names : Array[String] = []
  let label_indices : Array[Int] = []
  for cmd_idx = 0; cmd_idx < commands.length(); cmd_idx = cmd_idx + 1 {
    match commands[cmd_idx].kind {
      Label(name) => {
        label_names.push(name)
        label_indices.push(cmd_idx)
      }
      _ => ()
    }
  }

  let mut line_idx = 0
  while line_idx < total_lines {
    let mut line_no = line_idx + 1
    let mut line = lines[line_idx].0
    let mut line_terminated = lines[line_idx].1
    let mut deleted = false
    let mut consumed_extra = 0
    let mut substituted = false
    let mut stop_after_cycle = false
    let mut append_queue : Array[String] = []

    let mut cmd_idx = 0
    while cmd_idx < commands.length() {
      executed_steps += 1
      if executed_steps > 2000 {
        self.stderr_buf.write_string("sed: command limit exceeded\n")
        self.exit_code = 1
        deleted = true
        stop_after_cycle = true
        break
      }

      let cmd = commands[cmd_idx]
      let (applies, next_state, next_last_regex) = sed_address_applies(
        cmd.address,
        line,
        line_no,
        total_lines,
        range_states[cmd_idx],
        last_regex,
      )
      range_states[cmd_idx] = next_state
      last_regex = next_last_regex
      let should_apply = if cmd.negated { not(applies) } else { applies }
      if not(should_apply) {
        match cmd.kind {
          GroupStart => {
            let end_idx = sed_find_group_end(commands, cmd_idx)
            if end_idx < 0 {
              self.stderr_buf.write_string("sed: invalid script\n")
              self.exit_code = 1
              deleted = true
              stop_after_cycle = true
              break
            }
            cmd_idx = end_idx + 1
          }
          _ => cmd_idx += 1
        }
        continue
      }

      match cmd.kind {
        GroupStart => ()
        GroupEnd => ()
        Delete => {
          for rest_idx = cmd_idx + 1; rest_idx < commands.length(); rest_idx = rest_idx + 1 {
            let (next_state, next_last_regex) = sed_address_tick_skipped(
              commands[rest_idx].address,
              line,
              line_no,
              total_lines,
              range_states[rest_idx],
              last_regex,
            )
            range_states[rest_idx] = next_state
            last_regex = next_last_regex
          }
          deleted = true
          break
        }
        DeleteFirstLine => {
          let nl_idx = sed_find_newline(line)
          if nl_idx < 0 {
            for rest_idx = cmd_idx + 1; rest_idx < commands.length(); rest_idx = rest_idx + 1 {
              let (next_state, next_last_regex) = sed_address_tick_skipped(
                commands[rest_idx].address,
                line,
                line_no,
                total_lines,
                range_states[rest_idx],
                last_regex,
              )
              range_states[rest_idx] = next_state
              last_regex = next_last_regex
            }
            deleted = true
            break
          }
          line = substring_slice(line, nl_idx + 1, line.length())
          cmd_idx = 0
          continue
        }
        Substitute(subst) => {
          let matcher = match subst.matcher {
            Some(explicit_matcher) => {
              last_regex = Some(explicit_matcher)
              explicit_matcher
            }
            None => match last_regex {
              Some(previous_matcher) => previous_matcher
              None => {
                self.stderr_buf.write_string("sed: no previous regular expression\n")
                self.exit_code = 1
                deleted = true
                stop_after_cycle = true
                break
              }
            }
          }
          let (new_line, replaced) = sed_substitute_line(
            line,
            matcher,
            subst.replacement,
            subst.global,
            subst.occurrence,
            literal_ampersand=subst.literal_ampersand,
          )
          line = new_line
          if replaced {
            substituted = true
            if subst.print_on_subst {
              pending_no_newline = sed_emit_chunk(
                out,
                line,
                line_terminated,
                pending_no_newline,
              )
            }
            match subst.write_file {
              Some(path) => self.sed_append_write(path, line, line_terminated)
              None => ()
            }
          }
        }
        AppendNextLine => {
          let next_idx = line_idx + consumed_extra + 1
          if next_idx < total_lines {
            line = line + "\n" + lines[next_idx].0
            line_terminated = lines[next_idx].1
            consumed_extra += 1
            line_no = next_idx + 1
          } else {
            stop_after_cycle = true
            break
          }
        }
        NextLine => {
          if not(quiet) {
            pending_no_newline = sed_emit_chunk(
              out,
              line,
              line_terminated,
              pending_no_newline,
            )
          }
          for text in append_queue {
            pending_no_newline = sed_emit_chunk(out, text, true, pending_no_newline)
          }
          append_queue = []
          let next_idx = line_idx + consumed_extra + 1
          if next_idx >= total_lines {
            deleted = true
            stop_after_cycle = true
            break
          }
          line = lines[next_idx].0
          line_terminated = lines[next_idx].1
          consumed_extra += 1
          line_no = next_idx + 1
          substituted = false
        }
        Transliterate(spec) => {
          line = sed_transliterate_line(line, spec.source, spec.target)
        }
        PrintPattern => {
          pending_no_newline = sed_emit_chunk(out, line, line_terminated, pending_no_newline)
        }
        PrintFirstLine => {
          let nl_idx = sed_find_newline(line)
          if nl_idx < 0 {
            pending_no_newline = sed_emit_chunk(
              out,
              line,
              line_terminated,
              pending_no_newline,
            )
          } else {
            pending_no_newline = sed_emit_chunk(
              out,
              substring_slice(line, 0, nl_idx),
              true,
              pending_no_newline,
            )
          }
        }
        PrintLineNumber => {
          pending_no_newline = sed_emit_chunk(
            out,
            line_no.to_string(),
            true,
            pending_no_newline,
          )
        }
        HoldSet => {
          hold_space = line
        }
        HoldAppend => {
          hold_space = if hold_space.length() == 0 {
            line
          } else {
            hold_space + "\n" + line
          }
        }
        HoldGet => {
          line = hold_space
          line_terminated = true
        }
        HoldAppendGet => {
          line = line + "\n" + hold_space
          line_terminated = true
        }
        ExchangeHold => {
          let old_line = line
          line = hold_space
          hold_space = old_line
          line_terminated = true
        }
        AppendText(text) => append_queue.push(text)
        InsertText(text) => {
          pending_no_newline = sed_emit_chunk(out, text, true, pending_no_newline)
        }
        ChangeText(text) => {
          pending_no_newline = sed_emit_chunk(out, text, true, pending_no_newline)
          deleted = true
          break
        }
        WriteFile(path) => {
          self.sed_append_write(path, line, line_terminated)
        }
        Label(_) => ()
        Branch(label) => {
          match label {
            None => break
            Some(name) => {
              let target = sed_find_label_index(label_names, label_indices, name)
              if target < 0 {
                self.stderr_buf.write_string("sed: can't find label \{name}\n")
                self.exit_code = 1
                deleted = true
                stop_after_cycle = true
                break
              }
              cmd_idx = target
              continue
            }
          }
        }
        BranchIfSubst(label) => {
          let should_branch = substituted
          substituted = false
          if should_branch {
            match label {
              None => break
              Some(name) => {
                let target = sed_find_label_index(label_names, label_indices, name)
                if target < 0 {
                  self.stderr_buf.write_string("sed: can't find label \{name}\n")
                  self.exit_code = 1
                  deleted = true
                  stop_after_cycle = true
                  break
                }
                cmd_idx = target
                continue
              }
            }
          }
        }
        BranchIfNotSubst(label) => {
          let should_branch = not(substituted)
          substituted = false
          if should_branch {
            match label {
              None => break
              Some(name) => {
                let target = sed_find_label_index(label_names, label_indices, name)
                if target < 0 {
                  self.stderr_buf.write_string("sed: can't find label \{name}\n")
                  self.exit_code = 1
                  deleted = true
                  stop_after_cycle = true
                  break
                }
                cmd_idx = target
                continue
              }
            }
          }
        }
        VersionCheck(required) => {
          if not(sed_version_supported(required)) {
            self.stderr_buf.write_string("sed: version check failed\n")
            self.exit_code = 1
            deleted = true
            stop_after_cycle = true
            break
          }
        }
        Quit => {
          if not(quiet) {
            pending_no_newline = sed_emit_chunk(
              out,
              line,
              line_terminated,
              pending_no_newline,
            )
          }
          deleted = true
          quit = true
          break
        }
      }
      cmd_idx += 1
    }

    if not(deleted) && not(quiet) {
      pending_no_newline = sed_emit_chunk(out, line, line_terminated, pending_no_newline)
    }
    for text in append_queue {
      pending_no_newline = sed_emit_chunk(out, text, true, pending_no_newline)
    }

    line_idx += consumed_extra + 1
    if quit || stop_after_cycle {
      break
    }
  }

  (out.to_string(), pending_no_newline)
}

fn parse_sed_inline_directives(expr : String) -> (Bool, Bool)? {
  let trimmed = trim_ascii_left(expr)
  if trimmed.length() < 2 || trimmed[0].to_int().unsafe_to_char() != '#' {
    return None
  }

  let mut quiet = false
  let mut extended = false
  let mut saw_flag = false
  let mut i = 1
  while i < trimmed.length() {
    let ch = trimmed[i].to_int().unsafe_to_char()
    match ch {
      'n' => {
        quiet = true
        saw_flag = true
      }
      'r' | 'E' => {
        extended = true
        saw_flag = true
      }
      ' ' | '\t' | '\r' | '\n' => ()
      _ => return None
    }
    i += 1
  }

  if saw_flag {
    Some((quiet, extended))
  } else {
    None
  }
}

fn sed_version_supported(required : String?) -> Bool {
  match required {
    None => true
    Some(text) => {
      guard parse_sed_version_triplet(text) is Some((major, minor, patch)) else {
        return false
      }
      if major < 4 {
        true
      } else if major > 4 {
        false
      } else if minor < 5 {
        true
      } else if minor > 5 {
        false
      } else {
        patch <= 3
      }
    }
  }
}

fn parse_sed_version_triplet(text : String) -> (Int, Int, Int)? {
  let trimmed = trim_ascii_space(text)
  if trimmed.length() == 0 {
    return None
  }

  let parts : Array[Int] = []
  let mut segment_start = 0
  let mut i = 0
  while i <= trimmed.length() {
    let at_end = i == trimmed.length()
    let ch = if at_end { '.' } else { trimmed[i].to_int().unsafe_to_char() }
    if ch == '.' || at_end {
      if i == segment_start {
        return None
      }
      let segment = substring_slice(trimmed, segment_start, i)
      for j = 0; j < segment.length(); j = j + 1 {
        let digit = segment[j].to_int().unsafe_to_char()
        if digit < '0' || digit > '9' {
          return None
        }
      }
      parts.push(parse_int_str(segment))
      if parts.length() > 3 {
        return None
      }
      segment_start = i + 1
    } else if ch < '0' || ch > '9' {
      return None
    }
    i += 1
  }

  if parts.length() == 0 {
    return None
  }
  let major = parts[0]
  let minor = if parts.length() >= 2 { parts[1] } else { 0 }
  let patch = if parts.length() >= 3 { parts[2] } else { 0 }
  Some((major, minor, patch))
}

fn sed_emit_chunk(
  out : StringBuilder,
  text : String,
  terminated : Bool,
  pending_no_newline : Bool
) -> Bool {
  if pending_no_newline {
    out.write_char('\n')
  }
  out.write_string(text)
  if terminated {
    out.write_char('\n')
    false
  } else {
    true
  }
}

fn sed_find_newline(text : String) -> Int {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int().unsafe_to_char() == '\n' {
      return i
    }
  }
  -1
}

fn sed_find_label_index(
  names : Array[String],
  indices : Array[Int],
  label : String
) -> Int {
  for i = 0; i < names.length(); i = i + 1 {
    if names[i] == label {
      return indices[i]
    }
  }
  -1
}

fn sed_find_group_end(commands : Array[SedCommand], start_idx : Int) -> Int {
  let mut depth = 0
  for i = start_idx; i < commands.length(); i = i + 1 {
    match commands[i].kind {
      GroupStart => depth += 1
      GroupEnd => {
        depth -= 1
        if depth == 0 {
          return i
        }
      }
      _ => ()
    }
  }
  -1
}

fn sed_find_missing_branch_label(commands : Array[SedCommand]) -> String? {
  let labels : Array[String] = []
  for cmd in commands {
    match cmd.kind {
      Label(name) => labels.push(name)
      _ => ()
    }
  }

  for cmd in commands {
    match cmd.kind {
      Branch(label) | BranchIfSubst(label) | BranchIfNotSubst(label) => {
        match label {
          Some(name) => {
            let mut found = false
            for known in labels {
              if known == name {
                found = true
                break
              }
            }
            if not(found) {
              return Some(name)
            }
          }
          None => ()
        }
      }
      _ => ()
    }
  }

  None
}

fn sed_split_lines_with_flags(input : String) -> Array[(String, Bool)] {
  let lines : Array[(String, Bool)] = []
  if input.length() == 0 {
    return lines
  }

  let buf = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      lines.push((buf.to_string(), true))
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }

  let remaining = buf.to_string()
  if remaining.length() > 0 {
    lines.push((remaining, false))
  }
  lines
}

fn ExecContext::sed_append_write(
  self : ExecContext,
  path : String,
  text : String,
  terminated : Bool
) -> Unit {
  let resolved = try {
    @fs.resolve_path(self.cwd, path)
  } catch {
    _ => path
  }

  let existing = match self.fs.entries.get(resolved) {
    Some(@fs.FsEntry::File(file)) => file.content
    _ => ""
  }
  let next = StringBuilder::new()
  next.write_string(existing)
  if existing.length() > 0 &&
    existing[existing.length() - 1].to_int().unsafe_to_char() != '\n' {
    next.write_char('\n')
  }
  next.write_string(text)
  if terminated {
    next.write_char('\n')
  }
  try {
    self.fs.write_file(resolved, next.to_string())
  } catch {
    _ => ()
  }
}

fn is_sed_script_prefix_valid(expr : String) -> Bool {
  if expr.length() == 0 {
    return true
  }

  let ch = expr[0].to_int().unsafe_to_char()
  if ch == '#' || ch == '/' || ch == '$' || ch == '{' || ch == '}' || ch == ':' || ch == '!' {
    return true
  }
  if ch >= '0' && ch <= '9' {
    return true
  }
  if ch == 'w' {
    if expr.length() == 1 {
      return true
    }
    let next = expr[1].to_int().unsafe_to_char()
    return next == ' ' || next == '\t' || next == '/' || next == '.' || next == '-'
  }
  ch == 's' ||
  ch == 'd' ||
  ch == 'D' ||
  ch == 'N' ||
  ch == 'n' ||
  ch == 'y' ||
  ch == '=' ||
  ch == 'p' ||
  ch == 'P' ||
  ch == 'h' ||
  ch == 'H' ||
  ch == 'g' ||
  ch == 'G' ||
  ch == 'x' ||
  ch == 'q' ||
  ch == 'a' ||
  ch == 'i' ||
  ch == 'c' ||
  ch == 'b' ||
  ch == 't' ||
  ch == 'T' ||
  ch == 'v'
}

fn parse_sed_script_commands(
  expr : String,
  extended~ : Bool = false
) -> Array[SedCommand]? {
  let normalized = trim_ascii_left(expr)
  if trim_ascii_space(normalized).length() == 0 {
    return Some([])
  }

  let (segments, separators) = split_sed_top_level_parts(normalized)
  if separators.length() == 0 {
    return parse_sed_single_piece(normalized, extended~)
  }

  let merged : Array[SedCommand] = []
  let mut seg_idx = 0
  while seg_idx < segments.length() {
    let mut candidate = segments[seg_idx]
    let mut sep_idx = seg_idx
    let mut parsed = parse_sed_single_piece(candidate, extended~)
    while parsed is None && sep_idx < separators.length() {
      if sep_idx - seg_idx >= 12 {
        return None
      }
      candidate = candidate + separators[sep_idx] + segments[sep_idx + 1]
      sep_idx += 1
      parsed = parse_sed_single_piece(candidate, extended~)
    }
    guard parsed is Some(cmds) else {
      return None
    }
    for cmd in cmds {
      merged.push(cmd)
    }
    seg_idx = sep_idx + 1
  }

  Some(merged)
}

fn parse_sed_single_piece(
  expr : String,
  extended~ : Bool = false
) -> Array[SedCommand]? {
  let trimmed = trim_ascii_left(expr)
  if trim_ascii_space(trimmed).length() == 0 {
    return Some([])
  }
  if trimmed[0].to_int().unsafe_to_char() == '#' {
    return Some([])
  }

  match parse_sed_command(trimmed, extended~) {
    Some(cmd) => return Some([cmd])
    None => ()
  }

  match parse_sed_group_commands(trimmed, extended~) {
    Some(cmds) => return Some(cmds)
    None => ()
  }

  None
}

fn parse_sed_group_commands(
  expr : String,
  extended~ : Bool = false
) -> Array[SedCommand]? {
  guard parse_sed_address_prefix(expr, extended~) is Some((address, cmd_idx)) else {
    return None
  }

  let mut open_idx = skip_ascii_space(expr, cmd_idx)
  let mut outer_negated = false
  if open_idx < expr.length() && expr[open_idx].to_int().unsafe_to_char() == '!' {
    outer_negated = true
    open_idx = skip_ascii_space(expr, open_idx + 1)
  }
  if outer_negated && address is None {
    return None
  }
  if open_idx >= expr.length() || expr[open_idx].to_int().unsafe_to_char() != '{' {
    return None
  }

  let mut depth = 1
  let mut i = open_idx + 1
  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()
    if ch == '\\' {
      i += 2
      continue
    }
    if ch == '{' {
      depth += 1
      i += 1
      continue
    }
    if ch == '}' {
      depth -= 1
      if depth == 0 {
        break
      }
      i += 1
      continue
    }
    i += 1
  }
  if depth != 0 {
    return None
  }

  let close_idx = i
  if skip_ascii_space(expr, close_idx + 1) != expr.length() {
    return None
  }

  let inner = substring_slice(expr, open_idx + 1, close_idx)
  guard parse_sed_script_commands(inner, extended~) is Some(inner_cmds) else {
    return None
  }

  let wrapped : Array[SedCommand] = []
  wrapped.push({
    address,
    kind: GroupStart,
    negated: outer_negated,
  })
  for cmd in inner_cmds {
    wrapped.push(cmd)
  }
  wrapped.push({
    address: None,
    kind: GroupEnd,
    negated: false,
  })
  Some(wrapped)
}

fn split_sed_top_level_parts(expr : String) -> (Array[String], Array[String]) {
  let segments : Array[String] = []
  let separators : Array[String] = []
  let mut start = 0
  let mut brace_depth = 0
  let mut escaped = false
  for i = 0; i < expr.length(); i = i + 1 {
    let ch = expr[i].to_int().unsafe_to_char()
    if escaped {
      escaped = false
      continue
    }
    if ch == '\\' {
      escaped = true
      continue
    }
    if ch == '{' {
      brace_depth += 1
      continue
    }
    if ch == '}' {
      if brace_depth > 0 {
        brace_depth -= 1
      }
      continue
    }
    if (ch == ';' || ch == '\n') && brace_depth == 0 {
      segments.push(substring_slice(expr, start, i))
      separators.push(if ch == ';' { ";" } else { "\n" })
      start = i + 1
    }
  }
  segments.push(substring_slice(expr, start, expr.length()))
  (segments, separators)
}

fn ExecContext::builtin_grep(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut invert = false
  let mut count_only = false
  let mut ignore_case = false
  let mut line_number = false
  let mut list_files_only = false
  let mut only_matching = false
  let mut word_match = false
  let mut no_filename = false
  let mut recursive = false
  let mut quiet = false
  let mut extended = false
  let mut fixed = false
  let mut before_context = 0
  let mut after_context = 0
  let include_globs : Array[String] = []
  let mut pattern = ""
  let file_args : Array[String] = []
  let mut pattern_set = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--include=") {
      include_globs.push(arg.substring(start=10))
    } else if arg == "--include" && i + 1 < args.length() {
      i += 1
      include_globs.push(args[i])
    } else if arg == "-v" {
      invert = true
    } else if arg == "-c" {
      count_only = true
    } else if arg == "-i" {
      ignore_case = true
    } else if arg == "-n" {
      line_number = true
    } else if arg == "-l" {
      list_files_only = true
    } else if arg == "-o" {
      only_matching = true
    } else if arg == "-w" {
      word_match = true
    } else if arg == "-h" {
      no_filename = true
    } else if arg == "-r" || arg == "-R" {
      recursive = true
    } else if arg == "-q" {
      quiet = true
    } else if arg == "-E" {
      extended = true
    } else if arg == "-F" {
      fixed = true
    } else if arg == "-A" && i + 1 < args.length() {
      i += 1
      after_context = parse_int_str(args[i])
    } else if arg == "-B" && i + 1 < args.length() {
      i += 1
      before_context = parse_int_str(args[i])
    } else if arg == "-C" && i + 1 < args.length() {
      i += 1
      let ctx = parse_int_str(args[i])
      before_context = ctx
      after_context = ctx
    } else if arg.has_prefix("-A") && arg.length() > 2 {
      after_context = parse_int_str(arg.substring(start=2))
    } else if arg.has_prefix("-B") && arg.length() > 2 {
      before_context = parse_int_str(arg.substring(start=2))
    } else if arg.has_prefix("-C") && arg.length() > 2 {
      let ctx = parse_int_str(arg.substring(start=2))
      before_context = ctx
      after_context = ctx
    } else if arg.length() > 1 && arg[0] == '-' {
      let mut consumed_value = false
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'v' => invert = true
          'c' => count_only = true
          'i' => ignore_case = true
          'n' => line_number = true
          'l' => list_files_only = true
          'o' => only_matching = true
          'w' => word_match = true
          'h' => no_filename = true
          'r' | 'R' => recursive = true
          'q' => quiet = true
          'E' => extended = true
          'F' => fixed = true
          'A' => {
            if j + 1 < arg.length() {
              after_context = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              after_context = parse_int_str(args[i])
            }
            consumed_value = true
          }
          'B' => {
            if j + 1 < arg.length() {
              before_context = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              before_context = parse_int_str(args[i])
            }
            consumed_value = true
          }
          'C' => {
            let ctx = if j + 1 < arg.length() {
              parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              parse_int_str(args[i])
            } else {
              0
            }
            before_context = ctx
            after_context = ctx
            consumed_value = true
          }
          _ => ()
        }
        if consumed_value {
          break
        }
      }
    } else if arg == "-e" && i + 1 < args.length() {
      i += 1
      pattern = args[i]
      pattern_set = true
    } else if not(pattern_set) {
      pattern = arg
      pattern_set = true
    } else {
      file_args.push(arg)
    }
    i += 1
  }

  if not(pattern_set) {
    self.stderr_buf.write_string("grep: missing pattern\n")
    self.exit_code = 2
    return
  }

  let matcher = try {
    @regex.compile_grep_matcher(
      pattern,
      extended~,
      fixed~,
      ignore_case~,
    )
  } catch {
    _ => {
      self.stderr_buf.write_string("grep: invalid regular expression\n")
      self.exit_code = 2
      return
    }
  }

  let targets : Array[GrepTarget] = []
  let mut had_io_error = false
  if file_args.length() == 0 {
    targets.push({ display_path: "", content: self.stdin_buf })
  } else {
    for raw_path in file_args {
      let resolved = try {
        @fs.resolve_path(self.cwd, raw_path)
      } catch {
        _ => raw_path
      }
      match self.fs.entries.get(resolved) {
        Some(@fs.FsEntry::Directory(_)) if recursive => {
          let mut prefix = resolved
          if not(prefix.has_suffix("/")) {
            prefix = prefix + "/"
          }
          let matched_paths : Array[String] = []
          for full_path, entry in self.fs.entries {
            if full_path.has_prefix(prefix) {
              match entry {
                @fs.FsEntry::File(_) => matched_paths.push(full_path)
                _ => ()
              }
            }
          }
          grep_sort_paths(matched_paths)
          for full_path in matched_paths {
            let display = grep_recursive_display_path(raw_path, resolved, full_path)
            if include_globs.length() > 0 {
              let base = path_basename(display)
              let mut include_match = false
              for glob in include_globs {
                if @fs.glob_match(glob, base) {
                  include_match = true
                  break
                }
              }
              if not(include_match) {
                continue
              }
            }
            match self.fs.entries.get(full_path) {
              Some(@fs.FsEntry::File(file)) =>
                targets.push({ display_path: display, content: file.content })
              _ => ()
            }
          }
        }
        Some(@fs.FsEntry::Directory(_)) => {
          self.stderr_buf.write_string("grep: \{raw_path}: Is a directory\n")
          had_io_error = true
        }
        _ => {
          let content = try {
            self.fs.read_file(resolved)
          } catch {
            @fs.FsError(msg) => {
              self.stderr_buf.write_string("grep: \{msg}\n")
              had_io_error = true
              continue
            }
          }
          targets.push({ display_path: raw_path, content })
        }
      }
    }
  }

  let show_filename = not(no_filename) && (targets.length() > 1 || recursive)
  let mut total_selected = 0

  for target in targets {
    let lines = split_lines_no_trailing(target.content)
    let line_matches : Array[Array[(Int, Int)]] = []
    let selected_lines : Array[Bool] = []
    let mut selected_count = 0

    for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
      let line = lines[line_idx]
      let raw_ranges = matcher.find_all(line)
      let ranges = filter_word_ranges(raw_ranges, line, word_match)
      let has_match = ranges.length() > 0
      let selected = if invert { not(has_match) } else { has_match }
      line_matches.push(ranges)
      selected_lines.push(selected)
      if selected {
        selected_count += 1
      }
    }

    if selected_count > 0 {
      total_selected += selected_count
    }

    if quiet && selected_count > 0 {
      self.exit_code = 0
      return
    }

    if list_files_only {
      if selected_count > 0 {
        self.stdout_buf.write_string(target.display_path + "\n")
      }
      continue
    }

    if count_only {
      if show_filename {
        self.stdout_buf.write_string(
          target.display_path + ":" + selected_count.to_string() + "\n",
        )
      } else {
        self.stdout_buf.write_string(selected_count.to_string() + "\n")
      }
      continue
    }

    if only_matching {
      for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
        if not(selected_lines[line_idx]) || invert {
          continue
        }
        let line = lines[line_idx]
        for range in line_matches[line_idx] {
          if range.1 <= range.0 {
            continue
          }
          let prefix = grep_output_prefix(
            target.display_path,
            line_idx + 1,
            show_filename,
            line_number,
          )
          let matched = substring_slice(line, range.0, range.1)
          self.stdout_buf.write_string(prefix + matched + "\n")
        }
      }
      continue
    }

    let mut print_mask = selected_lines
    if before_context > 0 || after_context > 0 {
      print_mask = Array::makei(lines.length(), _ => false)
      for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
        if selected_lines[line_idx] {
          let start = if line_idx - before_context < 0 {
            0
          } else {
            line_idx - before_context
          }
          let end = if line_idx + after_context >= lines.length() {
            lines.length() - 1
          } else {
            line_idx + after_context
          }
          for j = start; j <= end; j = j + 1 {
            print_mask[j] = true
          }
        }
      }
    }

    for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
      if not(print_mask[line_idx]) {
        continue
      }
      let prefix = grep_output_prefix(
        target.display_path,
        line_idx + 1,
        show_filename,
        line_number,
      )
      self.stdout_buf.write_string(prefix + lines[line_idx] + "\n")
    }
  }

  if had_io_error {
    self.exit_code = 2
  } else {
    self.exit_code = if total_selected > 0 { 0 } else { 1 }
  }
}
