// MoonBash Interpreter - Search Builtins
// Split from builtins_extra.mbt for maintainability.

fn ExecContext::builtin_sed(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let expressions : Array[String] = []
  let files : Array[String] = []
  let mut script_taken = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-e" && i + 1 < args.length() {
      i += 1
      expressions.push(args[i])
      script_taken = true
    } else if arg.has_prefix("-e") && arg.length() > 2 {
      expressions.push(arg.substring(start=2))
      script_taken = true
    } else if not(script_taken) {
      let mut candidate = arg
      let mut consumed = 0
      let mut parsed = parse_sed_command(candidate)
      while parsed is None && i + consumed + 1 < args.length() {
        consumed += 1
        candidate = candidate + " " + args[i + consumed]
        parsed = parse_sed_command(candidate)
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

  let commands : Array[SedCommand] = []
  for expr in expressions {
    let parsed = parse_sed_command(expr)
    match parsed {
      Some(cmd) => commands.push(cmd)
      None => {
        self.stderr_buf.write_string("sed: invalid script\n")
        self.exit_code = 1
        return
      }
    }
  }

  let inputs : Array[String] = []
  if files.length() == 0 {
    inputs.push(self.stdin_buf)
  } else {
    for path in files {
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
    }
  }

  for input in inputs {
    let lines = split_lines_no_trailing(input)
    let total_lines = lines.length()
    let range_states = Array::makei(commands.length(), _ => false)

    for line_idx = 0; line_idx < total_lines; line_idx = line_idx + 1 {
      let line_no = line_idx + 1
      let mut line = lines[line_idx]
      let mut deleted = false

      for cmd_idx = 0; cmd_idx < commands.length(); cmd_idx = cmd_idx + 1 {
        let cmd = commands[cmd_idx]
        let (applies, next_state) = sed_address_applies(
          cmd.address,
          line,
          line_no,
          total_lines,
          range_states[cmd_idx],
        )
        range_states[cmd_idx] = next_state
        if not(applies) {
          continue
        }

        match cmd.kind {
          Delete => {
            deleted = true
            break
          }
          Substitute(subst) => {
            let (new_line, _) = sed_substitute_line(
              line,
              subst.matcher,
              subst.replacement,
              subst.global,
            )
            line = new_line
          }
        }
      }

      if not(deleted) {
        self.stdout_buf.write_string(line + "\n")
      }
    }
  }

  self.exit_code = 0
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
  let mut include_glob : String? = None
  let mut pattern = ""
  let file_args : Array[String] = []
  let mut pattern_set = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--include=") {
      include_glob = Some(arg.substring(start=10))
    } else if arg == "--include" && i + 1 < args.length() {
      i += 1
      include_glob = Some(args[i])
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
          matched_paths.sort()
          for full_path in matched_paths {
            let display = to_display_path(self.cwd, full_path)
            match include_glob {
              Some(glob) => {
                if not(@fs.glob_match(glob, path_basename(display))) {
                  continue
                }
              }
              None => ()
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

