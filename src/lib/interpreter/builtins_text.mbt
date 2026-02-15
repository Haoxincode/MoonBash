// MoonBash Interpreter - Text Builtins
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

