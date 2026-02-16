// moon_bash Interpreter - Text Builtins (Transform and Streams)
// Split from builtins_text.mbt for maintainability.

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
  let mut complement_mode = false
  let mut arg_idx = 0
  while arg_idx < args.length() && args[arg_idx].length() > 1 && args[arg_idx][0] == '-' {
    for i = 1; i < args[arg_idx].length(); i = i + 1 {
      let flag = args[arg_idx][i].to_int().unsafe_to_char()
      match flag {
        'c' => complement_mode = true
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
  let squeeze_complement = if has_set2 { false } else { complement_mode }
  if squeeze_mode && not(tr_set_matches(squeeze_set, ' ', squeeze_complement)) {
    // Keep compatibility with quoted sets that include a trailing space.
    squeeze_set.push(' ')
  }
  let buf = StringBuilder::new()
  let mut prev_written : Char? = None
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if delete_mode && tr_set_matches(set1, ch, complement_mode) {
      continue
    }

    let mapped = if has_set2 {
      tr_translate_with_mode(set1, set2, ch, complement_mode)
    } else {
      ch
    }

    if squeeze_mode && tr_set_matches(squeeze_set, mapped, squeeze_complement) {
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
      compare_sort_text(key_a, key_b)
    }

    if cmp == 0 {
      cmp = compare_sort_text(a, b)
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
  let format_count = (value : Int) => {
    let text = value.to_string()
    let mut pad = 4 - text.length()
    if pad < 0 {
      pad = 0
    }
    let out = StringBuilder::new()
    for i = 0; i < pad; i = i + 1 {
      out.write_char(' ')
    }
    out.write_string(text)
    out.to_string()
  }
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
            self.stdout_buf.write_string(format_count(count) + " " + prev + "\n")
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
        self.stdout_buf.write_string(format_count(count) + " " + prev + "\n")
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
  let mut char_mode = false
  let mut char_ranges : Array[(Int, Int)] = []
  let mut input_file : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == "-d" && i + 1 < args.length() {
      delimiter = args[i + 1]
      i += 2
    } else if args[i] == "-f" && i + 1 < args.length() {
      fields = parse_field_spec(args[i + 1])
      i += 2
    } else if args[i] == "-c" && i + 1 < args.length() {
      char_mode = true
      char_ranges = parse_cut_char_spec(args[i + 1])
      i += 2
    } else if args[i].has_prefix("-d") {
      delimiter = args[i].substring(start=2)
      i += 1
    } else if args[i].has_prefix("-f") {
      fields = parse_field_spec(args[i].substring(start=2))
      i += 1
    } else if args[i].has_prefix("-c") {
      char_mode = true
      char_ranges = parse_cut_char_spec(args[i].substring(start=2))
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
    if char_mode {
      self.stdout_buf.write_string(cut_by_char_ranges(line, char_ranges) + "\n")
    } else {
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
  }
  self.exit_code = 0
}

fn parse_cut_char_spec(spec : String) -> Array[(Int, Int)] {
  let ranges : Array[(Int, Int)] = []
  for raw in split_string_by_delimiter(spec, ",") {
    if raw.length() == 0 {
      continue
    }
    let mut dash = -1
    for i = 0; i < raw.length(); i = i + 1 {
      if raw[i] == '-' {
        dash = i
        break
      }
    }
    if dash < 0 {
      let pos = parse_int_str(raw)
      ranges.push((pos, pos))
      continue
    }
    let left = substring_slice(raw, 0, dash)
    let right = substring_slice(raw, dash + 1, raw.length())
    let start = if left.length() == 0 { 1 } else { parse_int_str(left) }
    let end = if right.length() == 0 { -1 } else { parse_int_str(right) }
    ranges.push((start, end))
  }
  ranges
}

fn cut_by_char_ranges(line : String, ranges : Array[(Int, Int)]) -> String {
  if line.length() == 0 || ranges.length() == 0 {
    return ""
  }
  let selected : Array[Bool] = []
  for i = 0; i <= line.length(); i = i + 1 {
    selected.push(false)
  }

  for range in ranges {
    let (raw_start, raw_end) = range
    let start = if raw_start < 1 { 1 } else { raw_start }
    let end = if raw_end < 0 || raw_end > line.length() {
      line.length()
    } else {
      raw_end
    }
    if start > line.length() || start > end {
      continue
    }
    for pos = start; pos <= end; pos = pos + 1 {
      selected[pos] = true
    }
  }

  let out = StringBuilder::new()
  for pos = 1; pos <= line.length(); pos = pos + 1 {
    if selected[pos] {
      out.write_char(line[pos - 1].to_int().unsafe_to_char())
    }
  }
  out.to_string()
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
