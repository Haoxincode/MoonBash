// moon_bash Interpreter - Sed Executor

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

  let input_paths : Array[String] = []
  let inputs : Array[String] = []

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

priv struct SedRuntime {
  commands : Array[SedCommand]
  lines : Array[(String, Bool)]
  total_lines : Int
  range_states : Array[SedRangeState]
  label_names : Array[String]
  label_indices : Array[Int]
  out : StringBuilder
}

fn sed_build_runtime(commands : Array[SedCommand], input : String) -> SedRuntime {
  let lines = sed_split_lines_with_flags(input)
  let (label_names, label_indices) = sed_collect_label_table(commands)
  {
    commands,
    lines,
    total_lines: lines.length(),
    range_states: Array::makei(commands.length(), _ => sed_empty_range_state()),
    label_names,
    label_indices,
    out: StringBuilder::new(),
  }
}

fn sed_collect_label_table(commands : Array[SedCommand]) -> (Array[String], Array[Int]) {
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
  (label_names, label_indices)
}

fn sed_new_state() -> SedState {
  {
    hold_space: "",
    last_regex: None,
    pending_no_newline: false,
    quit: false,
    executed_steps: 0,
  }
}

fn sed_new_cycle(runtime : SedRuntime, line_idx : Int) -> SedCycle {
  {
    line_no: line_idx + 1,
    line: runtime.lines[line_idx].0,
    line_terminated: runtime.lines[line_idx].1,
    deleted: false,
    consumed_extra: 0,
    substituted: false,
    stop_after_cycle: false,
    append_queue: [],
  }
}

fn ExecContext::sed_render_input(
  self : ExecContext,
  commands : Array[SedCommand],
  input : String,
  quiet~ : Bool = false
) -> (String, Bool) {
  let runtime = sed_build_runtime(commands, input)
  let state = sed_new_state()

  let mut line_idx = 0
  while line_idx < runtime.total_lines {
    let cycle = sed_new_cycle(runtime, line_idx)

    let mut cmd_idx = 0
    while cmd_idx < runtime.commands.length() {
      state.executed_steps += 1
      if state.executed_steps > 2000 {
        let action = self.sed_cycle_error(cycle, "sed: command limit exceeded")
        if action is BreakCycle {
          break
        }
      }

      let cmd = runtime.commands[cmd_idx]
      let (applies, next_state, next_last_regex) = sed_address_applies(
        cmd.address,
        cycle.line,
        cycle.line_no,
        runtime.total_lines,
        runtime.range_states[cmd_idx],
        state.last_regex,
      )
      runtime.range_states[cmd_idx] = next_state
      state.last_regex = next_last_regex

      let should_apply = if cmd.negated { not(applies) } else { applies }
      let action = if should_apply {
        self.sed_execute_one_command(runtime, state, cycle, cmd, cmd_idx, line_idx, quiet~)
      } else {
        self.sed_skip_unmatched_command(runtime, cycle, cmd_idx)
      }

      match action {
        Next => cmd_idx += 1
        RestartCycle => {
          cmd_idx = 0
          continue
        }
        JumpTo(target) => {
          cmd_idx = target
          continue
        }
        BreakCycle | Quit => break
      }
    }

    if not(cycle.deleted) && not(quiet) {
      state.pending_no_newline = sed_emit_chunk(
        runtime.out,
        cycle.line,
        cycle.line_terminated,
        state.pending_no_newline,
      )
    }
    for text in cycle.append_queue {
      state.pending_no_newline = sed_emit_chunk(
        runtime.out,
        text,
        true,
        state.pending_no_newline,
      )
    }

    line_idx += cycle.consumed_extra + 1
    if state.quit || cycle.stop_after_cycle {
      break
    }
  }

  (runtime.out.to_string(), state.pending_no_newline)
}

fn ExecContext::sed_skip_unmatched_command(
  self : ExecContext,
  runtime : SedRuntime,
  cycle : SedCycle,
  cmd_idx : Int
) -> CycleAction {
  match runtime.commands[cmd_idx].kind {
    GroupStart => {
      let end_idx = sed_find_group_end(runtime.commands, cmd_idx)
      if end_idx < 0 {
        self.sed_cycle_error(cycle, "sed: invalid script")
      } else {
        JumpTo(end_idx + 1)
      }
    }
    _ => Next
  }
}

fn sed_tick_remaining_addresses(
  runtime : SedRuntime,
  cycle : SedCycle,
  start_idx : Int,
  last_regex : @regex.GrepMatcher?
) -> @regex.GrepMatcher? {
  let mut next_last = last_regex
  for rest_idx = start_idx + 1; rest_idx < runtime.commands.length(); rest_idx = rest_idx + 1 {
    let (next_state, tick_last_regex) = sed_address_tick_skipped(
      runtime.commands[rest_idx].address,
      cycle.line,
      cycle.line_no,
      runtime.total_lines,
      runtime.range_states[rest_idx],
      next_last,
    )
    runtime.range_states[rest_idx] = next_state
    next_last = tick_last_regex
  }
  next_last
}

fn ExecContext::sed_cycle_error(
  self : ExecContext,
  cycle : SedCycle,
  message : String
) -> CycleAction {
  self.stderr_buf.write_string(message + "\n")
  self.exit_code = 1
  cycle.deleted = true
  cycle.stop_after_cycle = true
  BreakCycle
}

fn ExecContext::sed_branch_action(
  self : ExecContext,
  runtime : SedRuntime,
  cycle : SedCycle,
  label : String?
) -> CycleAction {
  match label {
    None => BreakCycle
    Some(name) => {
      let target = sed_find_label_index(runtime.label_names, runtime.label_indices, name)
      if target < 0 {
        self.sed_cycle_error(cycle, "sed: can't find label \{name}")
      } else {
        JumpTo(target)
      }
    }
  }
}

fn ExecContext::sed_execute_one_command(
  self : ExecContext,
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  cmd : SedCommand,
  cmd_idx : Int,
  line_idx : Int,
  quiet~ : Bool = false
) -> CycleAction {
  match cmd.kind {
    GroupStart | GroupEnd => Next
    Delete => sed_execute_delete(runtime, state, cycle, cmd_idx)
    DeleteFirstLine => sed_execute_delete_first_line(runtime, state, cycle, cmd_idx)
    Substitute(subst) => self.sed_execute_substitute(runtime, state, cycle, subst)
    AppendNextLine => sed_execute_append_next_line(runtime, cycle, line_idx)
    NextLine => sed_execute_next_line(runtime, state, cycle, line_idx, quiet~)
    Transliterate(spec) => {
      cycle.line = sed_transliterate_line(cycle.line, spec.source, spec.target)
      Next
    }
    PrintPattern => sed_execute_print_pattern(runtime, state, cycle)
    PrintFirstLine => sed_execute_print_first_line(runtime, state, cycle)
    PrintLineNumber => sed_execute_print_line_number(runtime, state, cycle)
    HoldSet => sed_execute_hold_set(state, cycle)
    HoldAppend => sed_execute_hold_append(state, cycle)
    HoldGet => sed_execute_hold_get(state, cycle)
    HoldAppendGet => sed_execute_hold_append_get(state, cycle)
    ExchangeHold => sed_execute_exchange_hold(state, cycle)
    AppendText(text) => {
      cycle.append_queue.push(text)
      Next
    }
    InsertText(text) => sed_execute_insert_text(runtime, state, text)
    ChangeText(text) => sed_execute_change_text(runtime, state, cycle, text)
    WriteFile(path) => {
      self.sed_append_write(path, cycle.line, cycle.line_terminated)
      Next
    }
    Label(_) => Next
    Branch(label) => self.sed_branch_action(runtime, cycle, label)
    BranchIfSubst(label) => self.sed_execute_conditional_branch(
      runtime,
      cycle,
      label,
      branch_on_subst=true,
    )
    BranchIfNotSubst(label) => self.sed_execute_conditional_branch(
      runtime,
      cycle,
      label,
      branch_on_subst=false,
    )
    VersionCheck(required) => self.sed_execute_version_check(cycle, required)
    Quit => sed_execute_quit(runtime, state, cycle, quiet~)
  }
}

fn sed_execute_delete(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  cmd_idx : Int
) -> CycleAction {
  state.last_regex = sed_tick_remaining_addresses(runtime, cycle, cmd_idx, state.last_regex)
  cycle.deleted = true
  BreakCycle
}

fn sed_execute_delete_first_line(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  cmd_idx : Int
) -> CycleAction {
  let nl_idx = sed_find_newline(cycle.line)
  if nl_idx < 0 {
    state.last_regex = sed_tick_remaining_addresses(runtime, cycle, cmd_idx, state.last_regex)
    cycle.deleted = true
    BreakCycle
  } else {
    cycle.line = substring_slice(cycle.line, nl_idx + 1, cycle.line.length())
    RestartCycle
  }
}

fn ExecContext::sed_execute_substitute(
  self : ExecContext,
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  subst : SedSubstSpec
) -> CycleAction {
  let matcher = match subst.matcher {
    Some(explicit_matcher) => {
      state.last_regex = Some(explicit_matcher)
      explicit_matcher
    }
    None => match state.last_regex {
      Some(previous_matcher) => previous_matcher
      None => {
        return self.sed_cycle_error(cycle, "sed: no previous regular expression")
      }
    }
  }
  let (new_line, replaced) = sed_substitute_line(
    cycle.line,
    matcher,
    subst.replacement,
    subst.global,
    subst.occurrence,
    literal_ampersand=subst.literal_ampersand,
  )
  cycle.line = new_line
  if replaced {
    cycle.substituted = true
    if subst.print_on_subst {
      state.pending_no_newline = sed_emit_chunk(
        runtime.out,
        cycle.line,
        cycle.line_terminated,
        state.pending_no_newline,
      )
    }
    match subst.write_file {
      Some(path) => self.sed_append_write(path, cycle.line, cycle.line_terminated)
      None => ()
    }
  }
  Next
}

fn sed_execute_append_next_line(
  runtime : SedRuntime,
  cycle : SedCycle,
  line_idx : Int
) -> CycleAction {
  let next_idx = line_idx + cycle.consumed_extra + 1
  if next_idx < runtime.total_lines {
    cycle.line = cycle.line + "\n" + runtime.lines[next_idx].0
    cycle.line_terminated = runtime.lines[next_idx].1
    cycle.consumed_extra += 1
    cycle.line_no = next_idx + 1
    Next
  } else {
    cycle.stop_after_cycle = true
    BreakCycle
  }
}

fn sed_execute_next_line(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  line_idx : Int,
  quiet~ : Bool = false
) -> CycleAction {
  if not(quiet) {
    state.pending_no_newline = sed_emit_chunk(
      runtime.out,
      cycle.line,
      cycle.line_terminated,
      state.pending_no_newline,
    )
  }
  for text in cycle.append_queue {
    state.pending_no_newline = sed_emit_chunk(
      runtime.out,
      text,
      true,
      state.pending_no_newline,
    )
  }
  cycle.append_queue = []

  let next_idx = line_idx + cycle.consumed_extra + 1
  if next_idx >= runtime.total_lines {
    cycle.deleted = true
    cycle.stop_after_cycle = true
    BreakCycle
  } else {
    cycle.line = runtime.lines[next_idx].0
    cycle.line_terminated = runtime.lines[next_idx].1
    cycle.consumed_extra += 1
    cycle.line_no = next_idx + 1
    cycle.substituted = false
    Next
  }
}

fn sed_execute_print_pattern(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle
) -> CycleAction {
  state.pending_no_newline = sed_emit_chunk(
    runtime.out,
    cycle.line,
    cycle.line_terminated,
    state.pending_no_newline,
  )
  Next
}

fn sed_execute_print_first_line(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle
) -> CycleAction {
  let nl_idx = sed_find_newline(cycle.line)
  if nl_idx < 0 {
    state.pending_no_newline = sed_emit_chunk(
      runtime.out,
      cycle.line,
      cycle.line_terminated,
      state.pending_no_newline,
    )
  } else {
    state.pending_no_newline = sed_emit_chunk(
      runtime.out,
      substring_slice(cycle.line, 0, nl_idx),
      true,
      state.pending_no_newline,
    )
  }
  Next
}

fn sed_execute_print_line_number(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle
) -> CycleAction {
  state.pending_no_newline = sed_emit_chunk(
    runtime.out,
    cycle.line_no.to_string(),
    true,
    state.pending_no_newline,
  )
  Next
}

fn sed_execute_hold_set(state : SedState, cycle : SedCycle) -> CycleAction {
  state.hold_space = cycle.line
  Next
}

fn sed_execute_hold_append(state : SedState, cycle : SedCycle) -> CycleAction {
  state.hold_space = if state.hold_space.length() == 0 {
    cycle.line
  } else {
    state.hold_space + "\n" + cycle.line
  }
  Next
}

fn sed_execute_hold_get(state : SedState, cycle : SedCycle) -> CycleAction {
  cycle.line = state.hold_space
  cycle.line_terminated = true
  Next
}

fn sed_execute_hold_append_get(state : SedState, cycle : SedCycle) -> CycleAction {
  cycle.line = cycle.line + "\n" + state.hold_space
  cycle.line_terminated = true
  Next
}

fn sed_execute_exchange_hold(state : SedState, cycle : SedCycle) -> CycleAction {
  let old_line = cycle.line
  cycle.line = state.hold_space
  state.hold_space = old_line
  cycle.line_terminated = true
  Next
}

fn sed_execute_insert_text(
  runtime : SedRuntime,
  state : SedState,
  text : String
) -> CycleAction {
  state.pending_no_newline = sed_emit_chunk(runtime.out, text, true, state.pending_no_newline)
  Next
}

fn sed_execute_change_text(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  text : String
) -> CycleAction {
  state.pending_no_newline = sed_emit_chunk(runtime.out, text, true, state.pending_no_newline)
  cycle.deleted = true
  BreakCycle
}

fn ExecContext::sed_execute_conditional_branch(
  self : ExecContext,
  runtime : SedRuntime,
  cycle : SedCycle,
  label : String?,
  branch_on_subst~ : Bool = true
) -> CycleAction {
  let should_branch = if branch_on_subst {
    cycle.substituted
  } else {
    not(cycle.substituted)
  }
  cycle.substituted = false
  if should_branch {
    self.sed_branch_action(runtime, cycle, label)
  } else {
    Next
  }
}

fn ExecContext::sed_execute_version_check(
  self : ExecContext,
  cycle : SedCycle,
  required : String?
) -> CycleAction {
  if not(sed_version_supported(required)) {
    self.sed_cycle_error(cycle, "sed: version check failed")
  } else {
    Next
  }
}

fn sed_execute_quit(
  runtime : SedRuntime,
  state : SedState,
  cycle : SedCycle,
  quiet~ : Bool = false
) -> CycleAction {
  if not(quiet) {
    state.pending_no_newline = sed_emit_chunk(
      runtime.out,
      cycle.line,
      cycle.line_terminated,
      state.pending_no_newline,
    )
  }
  cycle.deleted = true
  state.quit = true
  Quit
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

fn sed_address_applies(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  state : SedRangeState,
  last_regex : @regex.GrepMatcher?
) -> (Bool, SedRangeState, @regex.GrepMatcher?) {
  match address {
    None => (
      true,
      sed_empty_range_state(),
      last_regex,
    )
    Some(addr) => match addr.end {
      None => {
        let (hit, next_last) = sed_address_matches(
          addr.start,
          line,
          line_no,
          total_lines,
          last_regex,
        )
        (
          hit,
          sed_empty_range_state(),
          next_last,
        )
      }
      Some(end_addr) => {
        if state.pending_single_line {
          (
            true,
            sed_empty_range_state(),
            last_regex,
          )
        } else if state.in_range {
          match end_addr {
            Relative(_) => {
              if state.relative_end_line >= 0 && line_no >= state.relative_end_line {
                (
                  true,
                  sed_empty_range_state(),
                  last_regex,
                )
              } else {
                (true, state, last_regex)
              }
            }
            _ => {
              let (end_hit, next_last) = sed_address_matches(
                end_addr,
                line,
                line_no,
                total_lines,
                last_regex,
              )
              (
                true,
                {
                  in_range: not(end_hit),
                  relative_end_line: -1,
                  pending_single_line: false,
                },
                next_last,
              )
            }
          }
        } else {
          let (start_hit, last_after_start) = sed_address_matches(
            addr.start,
            line,
            line_no,
            total_lines,
            last_regex,
          )
          if not(start_hit) {
            (
              false,
              sed_empty_range_state(),
              last_after_start,
            )
          } else {
            match end_addr {
              Relative(count) => {
                if count <= 0 {
                  (
                    true,
                    sed_empty_range_state(),
                    last_after_start,
                  )
                } else {
                  (
                    true,
                    {
                      in_range: true,
                      relative_end_line: line_no + count,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              Line(end_line) => {
                if end_line <= line_no {
                  (
                    true,
                    sed_empty_range_state(),
                    last_after_start,
                  )
                } else {
                  (
                    true,
                    {
                      in_range: true,
                      relative_end_line: -1,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              _ => {
                let (end_hit, last_after_end) = sed_address_matches(
                  end_addr,
                  line,
                  line_no,
                  total_lines,
                  last_after_start,
                )
                (
                  true,
                  {
                    in_range: not(end_hit),
                    relative_end_line: -1,
                    pending_single_line: false,
                  },
                  last_after_end,
                )
              }
            }
          }
        }
      }
    }
  }
}

fn sed_address_tick_skipped(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  state : SedRangeState,
  last_regex : @regex.GrepMatcher?
) -> (SedRangeState, @regex.GrepMatcher?) {
  match address {
    None => (
      sed_empty_range_state(),
      last_regex,
    )
    Some(addr) => match addr.end {
      None => {
        // Single-address commands do not carry range state across skipped cycles.
        (sed_empty_range_state(), last_regex)
      }
      Some(end_addr) => {
        if state.pending_single_line {
          (state, last_regex)
        } else if state.in_range {
          // When a previous command deleted the cycle, this command is not executed.
          // Keep range active; end-address checks happen only on executed cycles.
          (state, last_regex)
        } else {
          let (start_hit, last_after_start) = sed_address_matches(
            addr.start,
            line,
            line_no,
            total_lines,
            last_regex,
          )
          if not(start_hit) {
            (
              sed_empty_range_state(),
              last_after_start,
            )
          } else {
            match end_addr {
              Relative(count) => {
                if count <= 0 {
                  (
                    {
                      in_range: false,
                      relative_end_line: -1,
                      pending_single_line: true,
                    },
                    last_after_start,
                  )
                } else {
                  (
                    {
                      in_range: true,
                      relative_end_line: line_no + count,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              Line(end_line) => {
                if end_line <= line_no {
                  (
                    {
                      in_range: false,
                      relative_end_line: -1,
                      pending_single_line: true,
                    },
                    last_after_start,
                  )
                } else {
                  (
                    {
                      in_range: true,
                      relative_end_line: -1,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              _ => (
                { in_range: true, relative_end_line: -1, pending_single_line: false },
                last_after_start,
              )
            }
          }
        }
      }
    }
  }
}

fn sed_address_matches(
  address : SedAddress,
  line : String,
  line_no : Int,
  total_lines : Int,
  last_regex : @regex.GrepMatcher?
) -> (Bool, @regex.GrepMatcher?) {
  match address {
    Line(n) => (line_no == n, last_regex)
    LastLine => (line_no == total_lines, last_regex)
    Regex(matcher) => (matcher.find_first(line) is Some(_), Some(matcher))
    LastRegex => match last_regex {
      Some(matcher) => (matcher.find_first(line) is Some(_), last_regex)
      None => (false, None)
    }
    Relative(_) => (false, last_regex)
  }
}

fn sed_substitute_line(
  line : String,
  matcher : @regex.GrepMatcher,
  replacement : String,
  global : Bool,
  occurrence : Int,
  literal_ampersand~ : Bool = false
) -> (String, Bool) {
  if not(global) {
    if occurrence > 1 {
      let mut cursor = 0
      let mut seen = 0
      while cursor <= line.length() {
        match matcher.find_first_with_groups(line, start=cursor) {
          Some((start, end, groups)) => {
            seen += 1
            if seen == occurrence {
              let prefix = substring_slice(line, 0, start)
              let matched = substring_slice(line, start, end)
              let suffix = substring_slice(line, end, line.length())
              return (
                prefix +
                apply_sed_replacement(
                  replacement,
                  matched,
                  groups,
                  literal_ampersand~,
                ) +
                suffix,
                true,
              )
            }
            if end > start {
              cursor = end
            } else if start < line.length() {
              cursor = start + 1
            } else {
              break
            }
          }
          None => break
        }
      }
      return (line, false)
    }

    match matcher.find_first_with_groups(line) {
      Some((start, end, groups)) => {
        let prefix = substring_slice(line, 0, start)
        let matched = substring_slice(line, start, end)
        let suffix = substring_slice(line, end, line.length())
        (
          prefix +
          apply_sed_replacement(
            replacement,
            matched,
            groups,
            literal_ampersand~,
          ) +
          suffix,
          true,
        )
      }
      None => (line, false)
    }
  } else {
    let out = StringBuilder::new()
    let mut cursor = 0
    let mut changed = false
    let mut done = false
    let mut last_match_end = -1
    while not(done) {
      match matcher.find_first_with_groups(line, start=cursor) {
        Some((start, end, groups)) => {
          if start < cursor {
            done = true
          } else if start == end && start == last_match_end {
            if start < line.length() {
              out.write_char(line[start].to_int().unsafe_to_char())
              cursor = start + 1
            } else {
              cursor = line.length()
              done = true
            }
          } else {
            out.write_string(substring_slice(line, cursor, start))
            let matched = substring_slice(line, start, end)
            out.write_string(
              apply_sed_replacement(
                replacement,
                matched,
                groups,
                literal_ampersand~,
              ),
            )
            changed = true
            last_match_end = end
            if end > start {
              cursor = end
            } else if start < line.length() {
              out.write_char(line[start].to_int().unsafe_to_char())
              cursor = start + 1
            } else {
              cursor = line.length()
              done = true
            }
          }
        }
        None => done = true
      }
    }
    if cursor <= line.length() {
      out.write_string(substring_slice(line, cursor, line.length()))
    }
    if changed {
      (out.to_string(), true)
    } else {
      (line, false)
    }
  }
}

fn sed_transliterate_line(
  line : String,
  source : String,
  target : String
) -> String {
  if source.length() == 0 || target.length() == 0 {
    return line
  }
  let out = StringBuilder::new()
  for i = 0; i < line.length(); i = i + 1 {
    let ch = line[i]
    let mut replaced = false
    for j = 0; j < source.length(); j = j + 1 {
      if source[j] == ch {
        out.write_char(target[j].to_int().unsafe_to_char())
        replaced = true
        break
      }
    }
    if not(replaced) {
      out.write_char(ch.to_int().unsafe_to_char())
    }
  }
  out.to_string()
}

fn apply_sed_replacement(
  template : String,
  matched : String,
  groups : Array[String],
  literal_ampersand~ : Bool = false
) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < template.length() {
    let ch = template[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < template.length() {
        let next = template[i + 1].to_int().unsafe_to_char()
        if next == '0' {
          out.write_string(matched)
        } else if next >= '1' && next <= '9' {
          let group_idx = next.to_int() - '1'.to_int()
          if group_idx >= 0 && group_idx < groups.length() {
            out.write_string(groups[group_idx])
          }
        } else if next == 'n' {
          out.write_char('\n')
        } else if next == 't' {
          out.write_char('\t')
        } else if next == 'r' {
          out.write_char('\r')
        } else {
          out.write_char(next)
        }
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if ch == '&' && not(literal_ampersand) {
      out.write_string(matched)
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}
