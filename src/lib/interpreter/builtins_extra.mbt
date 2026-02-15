// MoonBash Interpreter - Extended Builtins
// Split from interpreter.mbt for maintainability.

fn ExecContext::builtin_basename(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("basename: missing operand\n")
    self.exit_code = 1
    return
  }
  let path = args[0]
  let mut name = @fs.basename(path)
  // Remove suffix if provided
  if args.length() > 1 {
    let suffix = args[1]
    if name.length() > suffix.length() && name.has_suffix(suffix) {
      name = name.substring(start=0, end=name.length() - suffix.length())
    }
  }
  self.stdout_buf.write_string(name + "\n")
  self.exit_code = 0
}

fn ExecContext::builtin_dirname(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("dirname: missing operand\n")
    self.exit_code = 1
    return
  }
  let path = args[0]
  let parent = @fs.parent_path(path)
  // dirname returns "." for paths without a slash
  let result = if parent == "/" && not(path.has_prefix("/")) {
    "."
  } else if parent == path {
    "."
  } else {
    parent
  }
  self.stdout_buf.write_string(result + "\n")
  self.exit_code = 0
}

fn ExecContext::builtin_seq(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("seq: missing operand\n")
    self.exit_code = 1
    return
  }
  let mut first = 1
  let mut incr = 1
  let mut last = 1
  if args.length() == 1 {
    last = parse_int_str(args[0])
  } else if args.length() == 2 {
    first = parse_int_str(args[0])
    last = parse_int_str(args[1])
  } else {
    first = parse_int_str(args[0])
    incr = parse_int_str(args[1])
    last = parse_int_str(args[2])
  }
  if incr == 0 {
    self.stderr_buf.write_string("seq: zero increment\n")
    self.exit_code = 1
    return
  }
  let mut i = first
  let mut count = 0
  while (incr > 0 && i <= last) || (incr < 0 && i >= last) {
    self.stdout_buf.write_string(i.to_string() + "\n")
    i += incr
    count += 1
    if count > self.limits.max_loop_iterations {
      break
    }
  }
  self.exit_code = 0
}

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
      let style = arg.substring(start=2)
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
      number_format = arg.substring(start=2)
      i += 1
      continue
    }
    if arg == "-w" && i + 1 < args.length() {
      width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-w") && arg.length() > 2 {
      width = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-s" && i + 1 < args.length() {
      separator = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-s") && arg.length() > 2 {
      separator = arg.substring(start=2)
      i += 1
      continue
    }
    if arg == "-v" && i + 1 < args.length() {
      current_number = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-v") && arg.length() > 2 {
      current_number = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-i" && i + 1 < args.length() {
      increment = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-i") && arg.length() > 2 {
      increment = parse_int_str(arg.substring(start=2))
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
      width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-w") && arg.length() > 2 {
      width = parse_int_str(arg.substring(start=2))
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
              width = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              width = parse_int_str(args[i])
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
      tab_width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      tab_width = parse_int_str(arg.substring(start=2))
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
      tab_width = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      tab_width = parse_int_str(arg.substring(start=2))
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
              tab_width = parse_int_str(arg.substring(start=j + 1))
            } else if i + 1 < args.length() {
              i += 1
              tab_width = parse_int_str(args[i])
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
      delimiter_spec = arg.substring(start=2)
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
              delimiter_spec = arg.substring(start=j + 1)
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
      separator = Some(arg.substring(start=2))
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
              separator = Some(arg.substring(start=j + 1))
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
      field1 = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-1") && arg.length() > 2 {
      field1 = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-2" && i + 1 < args.length() {
      field2 = parse_int_str(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-2") && arg.length() > 2 {
      field2 = parse_int_str(arg.substring(start=2))
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      delimiter = args[i + 1]
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      delimiter = arg.substring(start=2)
      i += 1
      continue
    }
    if arg == "-a" && i + 1 < args.length() {
      let side = parse_int_str(args[i + 1])
      if side == 1 {
        include_unpair_1 = true
      } else if side == 2 {
        include_unpair_2 = true
      }
      i += 2
      continue
    }
    if arg.has_prefix("-a") && arg.length() > 2 {
      let side = parse_int_str(arg.substring(start=2))
      if side == 1 {
        include_unpair_1 = true
      } else if side == 2 {
        include_unpair_2 = true
      }
      i += 1
      continue
    }
    if arg == "-v" && i + 1 < args.length() {
      let side = parse_int_str(args[i + 1])
      if side == 1 || side == 2 {
        only_unpair_file = Some(side)
      }
      i += 2
      continue
    }
    if arg.has_prefix("-v") && arg.length() > 2 {
      let side = parse_int_str(arg.substring(start=2))
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

fn ExecContext::builtin_tr(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("tr: missing operand\n")
    self.exit_code = 1
    return
  }

  let input = self.stdin_buf
  let mut delete_mode = false
  let mut squeeze_mode = false
  let mut arg_idx = 0
  while arg_idx < args.length() && args[arg_idx].length() > 1 && args[arg_idx][0] == '-' {
    for i = 1; i < args[arg_idx].length(); i = i + 1 {
      let flag = args[arg_idx][i].to_int().unsafe_to_char()
      match flag {
        'd' => delete_mode = true
        's' => squeeze_mode = true
        _ => ()
      }
    }
    arg_idx += 1
  }

  if arg_idx >= args.length() {
    self.stderr_buf.write_string("tr: missing operand\n")
    self.exit_code = 1
    return
  }

  let set1 = expand_tr_set(args[arg_idx])
  arg_idx += 1
  let mut has_set2 = false
  let mut set2 : Array[Char] = []
  if not(delete_mode) && arg_idx < args.length() {
    set2 = expand_tr_set(args[arg_idx])
    has_set2 = true
  }

  if not(delete_mode) && not(has_set2) && not(squeeze_mode) {
    self.stderr_buf.write_string("tr: missing operand after set1\n")
    self.exit_code = 1
    return
  }

  let squeeze_set = if delete_mode || not(has_set2) { set1 } else { set2 }
  if squeeze_mode && not(tr_set_contains(squeeze_set, ' ')) {
    // Keep compatibility with quoted sets that include a trailing space.
    squeeze_set.push(' ')
  }
  let buf = StringBuilder::new()
  let mut prev_written : Char? = None
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if delete_mode && tr_set_contains(set1, ch) {
      continue
    }

    let mapped = if has_set2 {
      tr_translate(set1, set2, ch)
    } else {
      ch
    }

    if squeeze_mode && tr_set_contains(squeeze_set, mapped) {
      match prev_written {
        Some(last) if last == mapped => continue
        _ => ()
      }
    }

    buf.write_char(mapped)
    prev_written = Some(mapped)
  }
  self.stdout_buf.write_string(buf.to_string())
  self.exit_code = 0
}

fn ExecContext::builtin_sort(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut reverse = false
  let mut numeric = false
  let mut unique = false
  let mut human = false
  let mut version = false
  let mut check_only = false
  let mut ignore_leading_blanks = false
  let mut key_field : Int? = None
  let mut delimiter : String? = None
  let mut input_file : String? = None

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "-k" && i + 1 < args.length() {
      key_field = Some(parse_int_str(args[i + 1]))
      i += 2
      continue
    }
    if arg.has_prefix("-k") && arg.length() > 2 {
      key_field = Some(parse_int_str(arg.substring(start=2)))
      i += 1
      continue
    }
    if arg == "-t" && i + 1 < args.length() {
      delimiter = Some(args[i + 1])
      i += 2
      continue
    }
    if arg.has_prefix("-t") && arg.length() > 2 {
      delimiter = Some(arg.substring(start=2))
      i += 1
      continue
    }
    if arg.length() > 1 && arg[0] == '-' {
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'r' => reverse = true
          'n' => numeric = true
          'u' => unique = true
          'h' => human = true
          'V' => version = true
          'c' => check_only = true
          'b' => ignore_leading_blanks = true
          _ => ()
        }
      }
    } else {
      input_file = Some(arg)
    }
    i += 1
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("sort: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)
  let sorted = lines
  let compare_lines = (a : String, b : String) => {
    let key_a = extract_sort_key(a, key_field, delimiter, ignore_leading_blanks)
    let key_b = extract_sort_key(b, key_field, delimiter, ignore_leading_blanks)

    let mut cmp = if version {
      compare_version_like(key_a, key_b)
    } else if human {
      compare_ints(parse_human_size(key_a), parse_human_size(key_b))
    } else if numeric {
      compare_ints(parse_int_str(key_a), parse_int_str(key_b))
    } else {
      compare_strings(key_a, key_b)
    }

    if cmp == 0 {
      cmp = compare_strings(a, b)
    }
    if reverse { -cmp } else { cmp }
  }

  if check_only {
    if sorted.length() > 1 {
      for j = 1; j < sorted.length(); j = j + 1 {
        if compare_lines(sorted[j - 1], sorted[j]) > 0 {
          let label = input_file.unwrap_or("(stdin)")
          let msg = "sort: \{label}:\{j + 1}: disorder: \{sorted[j]}\n"
          self.stderr_buf.write_string(msg)
          self.stdout_buf.write_string(msg)
          self.exit_code = 1
          return
        }
      }
    }
    self.exit_code = 0
    return
  }

  sorted.sort_by(compare_lines)

  let mut prev : String? = None
  for i = 0; i < sorted.length(); i = i + 1 {
    if unique {
      match prev {
        Some(last) if last == sorted[i] => continue
        _ => ()
      }
    }
    self.stdout_buf.write_string(sorted[i] + "\n")
    prev = Some(sorted[i])
  }
  self.exit_code = 0
}

fn ExecContext::builtin_uniq(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut count_mode = false
  let mut duplicates_only = false
  let mut unique_only = false
  let mut input_file : String? = None
  for arg in args {
    if arg.length() > 1 && arg[0] == '-' {
      for i = 1; i < arg.length(); i = i + 1 {
        let flag = arg[i].to_int().unsafe_to_char()
        match flag {
          'c' => count_mode = true
          'd' => duplicates_only = true
          'u' => unique_only = true
          _ => ()
        }
      }
    } else {
      input_file = Some(arg)
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("uniq: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)
  let mut prev = ""
  let mut count = 0
  let should_emit = (group_count : Int) => {
    if duplicates_only && unique_only {
      false
    } else if duplicates_only {
      group_count > 1
    } else if unique_only {
      group_count == 1
    } else {
      true
    }
  }

  for i = 0; i < lines.length(); i = i + 1 {
    if i == 0 || lines[i] != prev {
      if i > 0 {
        if should_emit(count) {
          if count_mode {
            self.stdout_buf.write_string("      \{count} \{prev}\n")
          } else {
            self.stdout_buf.write_string(prev + "\n")
          }
        }
      }
      prev = lines[i]
      count = 1
    } else {
      count += 1
    }
  }
  if lines.length() > 0 {
    if should_emit(count) {
      if count_mode {
        self.stdout_buf.write_string("      \{count} \{prev}\n")
      } else {
        self.stdout_buf.write_string(prev + "\n")
      }
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_cut(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut delimiter = "\t"
  let mut fields : Array[Int] = []
  let mut input_file : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == "-d" && i + 1 < args.length() {
      delimiter = args[i + 1]
      i += 2
    } else if args[i] == "-f" && i + 1 < args.length() {
      fields = parse_field_spec(args[i + 1])
      i += 2
    } else if args[i].has_prefix("-d") {
      delimiter = args[i].substring(start=2)
      i += 1
    } else if args[i].has_prefix("-f") {
      fields = parse_field_spec(args[i].substring(start=2))
      i += 1
    } else {
      input_file = Some(args[i])
      i += 1
    }
  }

  let input = match input_file {
    Some(path) => {
      let resolved = try {
        @fs.resolve_path(self.cwd, path)
      } catch {
        _ => path
      }
      try {
        self.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => {
          self.stderr_buf.write_string("cut: \{msg}\n")
          self.exit_code = 1
          return
        }
      }
    }
    None => self.stdin_buf
  }

  let lines = split_lines_no_trailing(input)
  for line in lines {
    let parts = split_string_by_delimiter(line, delimiter)
    let out_buf = StringBuilder::new()
    let mut first = true
    for field_num in fields {
      if field_num > 0 && field_num <= parts.length() {
        if not(first) {
          out_buf.write_string(delimiter)
        }
        out_buf.write_string(parts[field_num - 1])
        first = false
      }
    }
    self.stdout_buf.write_string(out_buf.to_string() + "\n")
  }
  self.exit_code = 0
}

fn ExecContext::builtin_tee(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut append = false
  let files : Array[String] = []
  for arg in args {
    if arg == "-a" {
      append = true
    } else {
      files.push(arg)
    }
  }

  let input = self.stdin_buf
  // Write to stdout
  self.stdout_buf.write_string(input)
  // Write to files
  for file in files {
    let resolved = try {
      @fs.resolve_path(self.cwd, file)
    } catch {
      _ => file
    }
    try {
      if append {
        self.fs.append_file(resolved, input)
      } else {
        self.fs.write_file(resolved, input)
      }
    } catch {
      @fs.FsError(msg) =>
        self.stderr_buf.write_string("tee: \{msg}\n")
    }
  }
  self.exit_code = 0
}

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

fn ExecContext::builtin_xargs(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let cmd_name = if args.length() > 0 { args[0] } else { "echo" }
  let cmd_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }

  let input_words = split_by_whitespace(self.stdin_buf)
  for word in input_words {
    cmd_args.push(word)
  }
  self.run_command(cmd_name, cmd_args)
}

fn ExecContext::builtin_date(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  self.stdout_buf.write_string("Thu Jan  1 00:00:00 UTC 1970\n")
  self.exit_code = 0
}

fn ExecContext::builtin_env(
  self : ExecContext,
  _args : Array[String]
) -> Unit {
  for k, v in self.env {
    self.stdout_buf.write_string("\{k}=\{v}\n")
  }
  self.exit_code = 0
}

fn ExecContext::builtin_which(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  for arg in args {
    if is_shell_builtin(arg) || @commands.find_command(arg) is Some(_) {
      self.stdout_buf.write_string("/usr/bin/\{arg}\n")
    } else {
      self.stderr_buf.write_string("which: no \{arg} in PATH\n")
      self.exit_code = 1
    }
  }
  if self.exit_code != 1 {
    self.exit_code = 0
  }
}

