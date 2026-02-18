// moon_bash Interpreter - Text Builtins
// Split from builtins_extra.mbt for maintainability.

fn ExecContext::builtin_rev(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let input = if args.length() > 0 {
    // Read from file
    let path = try {
      @fs.resolve_path(self.cwd, args[0])
    } catch {
      _ => args[0]
    }
    try {
      self.fs.read_file(path)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("rev: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
  } else {
    self.stdin_buf
  }
  let lines = split_lines(input)
  for line in lines {
    let reversed = reverse_string(line)
    self.stdout_buf.write_string(reversed + "\n")
  }
  self.exit_code = 0
}

fn ExecContext::builtin_nl(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut number_all = false
  let mut number_format = "rn"
  let mut width = 6
  let mut separator = "\t"
  let mut current_number = 1
  let mut increment = 1
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-b" && i + 1 < args.length() {
      let style = args[i + 1]
      number_all = style == "a"
      i += 2
      continue
    }
    if arg.has_prefix("-b") && arg.length() > 2 {
      let style = arg.view(start_offset=2).to_string()
      number_all = style == "a"
      i += 1
      continue
    }
    if arg == "-n" && i + 1 < args.length() {
      number_format = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-n") && arg.length() > 2 {
      number_format = arg.view(start_offset=2).to_string()
      i += 1
      continue
    }
    if arg == "-w" && i + 1 < args.length() {
      width = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-w") && arg.length() > 2 {
      width = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg == "-s" && i + 1 < args.length() {
      separator = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-s") && arg.length() > 2 {
      separator = arg.view(start_offset=2).to_string()
      i += 1
      continue
    }
    if arg == "-v" && i + 1 < args.length() {
      current_number = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-v") && arg.length() > 2 {
      current_number = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg == "-i" && i + 1 < args.length() {
      increment = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-i") && arg.length() > 2 {
      increment = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if width < 0 {
    width = 0
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
          self.stderr_buf.write_string("nl: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
      inputs.push(content)
    }
  }

  for input in inputs {
    let lines = split_lines_no_trailing(input)
    for line in lines {
      let should_number = number_all || line.length() > 0
      if should_number {
        self.stdout_buf.write_string(
          format_nl_number(current_number, width, number_format),
        )
        current_number += increment
      } else {
        self.stdout_buf.write_string(repeat_char(' ', width))
      }
      self.stdout_buf.write_string(separator)
      self.stdout_buf.write_string(line)
      self.stdout_buf.write_char('\n')
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_fold(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut width = 80
  let mut break_spaces = false
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-s" {
      break_spaces = true
      i += 1
      continue
    }
    if arg == "-w" && i + 1 < args.length() {
      width = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-w") && arg.length() > 2 {
      width = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      let mut consumed_value = false
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          's' => break_spaces = true
          'w' => {
            if j + 1 < arg.length() {
              width = parse_int32_str(arg.view(start_offset=j + 1).to_string())
            } else if i + 1 < args.length() {
              i += 1
              width = parse_int32_str(args[i])
            }
            consumed_value = true
            break
          }
          _ => ()
        }
      }
      i += 1
      if consumed_value {
        continue
      }
      continue
    }
    files.push(arg)
    i += 1
  }

  if width <= 0 {
    width = 1
  }

  if files.length() == 0 {
    self.stdout_buf.write_string(fold_text(self.stdin_buf, width, break_spaces))
    self.exit_code = 0
    return
  }

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
        self.stderr_buf.write_string("fold: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    self.stdout_buf.write_string(fold_text(content, width, break_spaces))
  }

  self.exit_code = 0
}

fn ExecContext::builtin_expand(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut tab_width = 8
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-t" && i + 1 < args.length() {
      tab_width = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      tab_width = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if tab_width <= 0 {
    tab_width = 8
  }

  if files.length() == 0 {
    self.stdout_buf.write_string(expand_tabs(self.stdin_buf, tab_width))
    self.exit_code = 0
    return
  }

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
        self.stderr_buf.write_string("expand: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    self.stdout_buf.write_string(expand_tabs(content, tab_width))
  }

  self.exit_code = 0
}

fn ExecContext::builtin_unexpand(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut convert_all = false
  let mut tab_width = 8
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-a" {
      convert_all = true
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      tab_width = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      tab_width = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'a' => convert_all = true
          't' => {
            if j + 1 < arg.length() {
              tab_width = parse_int32_str(arg.view(start_offset=j + 1).to_string())
            } else if i + 1 < args.length() {
              i += 1
              tab_width = parse_int32_str(args[i])
            }
            break
          }
          _ => ()
        }
      }
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if tab_width <= 0 {
    tab_width = 8
  }

  if files.length() == 0 {
    self.stdout_buf.write_string(
      unexpand_tabs(self.stdin_buf, tab_width, convert_all),
    )
    self.exit_code = 0
    return
  }

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
        self.stderr_buf.write_string("unexpand: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    self.stdout_buf.write_string(
      unexpand_tabs(content, tab_width, convert_all),
    )
  }

  self.exit_code = 0
}

fn ExecContext::builtin_paste(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut serial_mode = false
  let mut delimiter_spec = "\t"
  let sources : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-s" {
      serial_mode = true
      i += 1
      continue
    }
    if arg == "-d" && i + 1 < args.length() {
      delimiter_spec = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-d") && arg.length() > 2 {
      delimiter_spec = arg.view(start_offset=2).to_string()
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' && arg != "-" {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          's' => serial_mode = true
          'd' => {
            if j + 1 < arg.length() {
              delimiter_spec = arg.view(start_offset=j + 1).to_string()
            } else if i + 1 < args.length() {
              i += 1
              delimiter_spec = args[i]
            } else {
              delimiter_spec = ""
            }
            break
          }
          _ => ()
        }
      }
      i += 1
      continue
    }
    sources.push(arg)
    i += 1
  }

  if sources.length() == 0 {
    sources.push("-")
  }

  let source_is_stdin : Array[Bool] = []
  let source_lines : Array[Array[String]] = []
  for source in sources {
    if source == "-" {
      source_is_stdin.push(true)
      source_lines.push([])
      continue
    }
    let resolved = try {
      @fs.resolve_path(self.cwd, source)
    } catch {
      _ => source
    }
    let content = try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("paste: \{msg}\n")
        self.exit_code = 1
        return
      }
    }
    source_is_stdin.push(false)
    source_lines.push(split_lines_no_trailing(content))
  }

  let delimiters = parse_paste_delimiters(delimiter_spec)
  let stdin_lines = split_lines_no_trailing(self.stdin_buf)
  let mut stdin_cursor = 0

  if serial_mode {
    for source_idx = 0; source_idx < sources.length(); source_idx = source_idx + 1 {
      let lines : Array[String] = if source_is_stdin[source_idx] {
        let remaining : Array[String] = []
        for j = stdin_cursor; j < stdin_lines.length(); j = j + 1 {
          remaining.push(stdin_lines[j])
        }
        stdin_cursor = stdin_lines.length()
        remaining
      } else {
        source_lines[source_idx]
      }

      for line_idx = 0; line_idx < lines.length(); line_idx = line_idx + 1 {
        if line_idx > 0 && delimiters.length() > 0 {
          let delim = delimiters[(line_idx - 1) % delimiters.length()]
          self.stdout_buf.write_char(delim)
        }
        self.stdout_buf.write_string(lines[line_idx])
      }
      self.stdout_buf.write_char('\n')
    }
    self.exit_code = 0
    return
  }

  let mut row = 0
  while true {
    let row_values : Array[String] = []
    let mut row_has_data = false

    for source_idx = 0; source_idx < sources.length(); source_idx = source_idx + 1 {
      if source_is_stdin[source_idx] {
        if stdin_cursor < stdin_lines.length() {
          row_values.push(stdin_lines[stdin_cursor])
          stdin_cursor += 1
          row_has_data = true
        } else {
          row_values.push("")
        }
      } else {
        let lines = source_lines[source_idx]
        if row < lines.length() {
          row_values.push(lines[row])
          row_has_data = true
        } else {
          row_values.push("")
        }
      }
    }

    if not(row_has_data) {
      break
    }

    for col_idx = 0; col_idx < row_values.length(); col_idx = col_idx + 1 {
      if col_idx > 0 && delimiters.length() > 0 {
        let delim = delimiters[(col_idx - 1) % delimiters.length()]
        self.stdout_buf.write_char(delim)
      }
      self.stdout_buf.write_string(row_values[col_idx])
    }
    self.stdout_buf.write_char('\n')
    row += 1
  }

  self.exit_code = 0
}

fn ExecContext::builtin_column(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut table_mode = false
  let mut separator : String? = None
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-t" {
      table_mode = true
      i += 1
      continue
    }
    if arg == "-s" && i + 1 < args.length() {
      separator = Some(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-s") && arg.length() > 2 {
      separator = Some(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          't' => table_mode = true
          's' => {
            if j + 1 < arg.length() {
              separator = Some(arg.view(start_offset=j + 1).to_string())
            } else if i + 1 < args.length() {
              i += 1
              separator = Some(args[i])
            }
            break
          }
          _ => ()
        }
      }
      i += 1
      continue
    }
    files.push(arg)
    i += 1
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
          self.stderr_buf.write_string("column: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
      inputs.push(content)
    }
  }

  for input in inputs {
    if table_mode {
      self.stdout_buf.write_string(format_column_table(input, separator))
    } else {
      self.stdout_buf.write_string(input)
    }
  }

  self.exit_code = 0
}

fn ExecContext::builtin_join(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut field1 = 1
  let mut field2 = 1
  let mut delimiter = " "
  let mut include_unpair_1 = false
  let mut include_unpair_2 = false
  let mut only_unpair_file : Int? = None
  let files : Array[String] = []

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-1" && i + 1 < args.length() {
      field1 = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-1") && arg.length() > 2 {
      field1 = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg == "-2" && i + 1 < args.length() {
      field2 = parse_int32_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-2") && arg.length() > 2 {
      field2 = parse_int32_str(arg.view(start_offset=2).to_string())
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      delimiter = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      delimiter = arg.view(start_offset=2).to_string()
      i += 1
      continue
    }
    if arg == "-a" && i + 1 < args.length() {
      let side = parse_int32_str(args[i + 1])
      if side == 1 {
        include_unpair_1 = true
      } else if side == 2 {
        include_unpair_2 = true
      }
      i += 2
      continue
    }
    if arg.has_prefix("-a") && arg.length() > 2 {
      let side = parse_int32_str(arg.view(start_offset=2).to_string())
      if side == 1 {
        include_unpair_1 = true
      } else if side == 2 {
        include_unpair_2 = true
      }
      i += 1
      continue
    }
    if arg == "-v" && i + 1 < args.length() {
      let side = parse_int32_str(args[i + 1])
      if side == 1 || side == 2 {
        only_unpair_file = Some(side)
      }
      i += 2
      continue
    }
    if arg.has_prefix("-v") && arg.length() > 2 {
      let side = parse_int32_str(arg.view(start_offset=2).to_string())
      if side == 1 || side == 2 {
        only_unpair_file = Some(side)
      }
      i += 1
      continue
    }
    files.push(arg)
    i += 1
  }

  if files.length() < 2 {
    self.stderr_buf.write_string("join: missing operand\n")
    self.exit_code = 1
    return
  }

  let read_join_file = (path : String) => {
    let resolved = try {
      @fs.resolve_path(self.cwd, path)
    } catch {
      _ => path
    }
    try {
      self.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => {
        self.stderr_buf.write_string("join: \{msg}\n")
        self.exit_code = 1
        ""
      }
    }
  }

  let content1 = read_join_file(files[0])
  if self.exit_code != 0 {
    return
  }
  let content2 = read_join_file(files[1])
  if self.exit_code != 0 {
    return
  }

  let lines1 = split_lines_no_trailing(content1)
  let lines2 = split_lines_no_trailing(content2)
  let rows1 : Array[Array[String]] = []
  let rows2 : Array[Array[String]] = []
  for line in lines1 {
    rows1.push(split_join_fields(line, delimiter))
  }
  for line in lines2 {
    rows2.push(split_join_fields(line, delimiter))
  }

  let join_idx1 = if field1 > 0 { field1 - 1 } else { 0 }
  let join_idx2 = if field2 > 0 { field2 - 1 } else { 0 }
  let mut idx1 = 0
  let mut idx2 = 0

  let should_emit_unpair = (source : Int) => {
    match only_unpair_file {
      Some(side) => side == source
      None => if source == 1 { include_unpair_1 } else { include_unpair_2 }
    }
  }

  while idx1 < rows1.length() && idx2 < rows2.length() {
    let key1 = join_field_value(rows1[idx1], join_idx1)
    let key2 = join_field_value(rows2[idx2], join_idx2)
    let cmp = compare_strings(key1, key2)
    if cmp == 0 {
      if only_unpair_file is None {
        let line = format_join_line(
          rows1[idx1],
          rows2[idx2],
          join_idx1,
          join_idx2,
          delimiter,
        )
        self.stdout_buf.write_string(line + "\n")
      }
      idx1 += 1
      idx2 += 1
    } else if cmp < 0 {
      if should_emit_unpair(1) {
        self.stdout_buf.write_string(lines1[idx1] + "\n")
      }
      idx1 += 1
    } else {
      if should_emit_unpair(2) {
        self.stdout_buf.write_string(lines2[idx2] + "\n")
      }
      idx2 += 1
    }
  }

  while idx1 < rows1.length() {
    if should_emit_unpair(1) {
      self.stdout_buf.write_string(lines1[idx1] + "\n")
    }
    idx1 += 1
  }
  while idx2 < rows2.length() {
    if should_emit_unpair(2) {
      self.stdout_buf.write_string(lines2[idx2] + "\n")
    }
    idx2 += 1
  }

  self.exit_code = 0
}

