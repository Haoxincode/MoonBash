// moon_bash Interpreter - Builtins (I/O and Meta)
// Split from builtins_core.mbt for maintainability.

fn ExecContext::builtin_read(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let input = self.stdin_buf
  // Find first line
  let mut line_end = input.length()
  for i = 0; i < input.length(); i = i + 1 {
    if input[i] == '\n' {
      line_end = i
      break
    }
  }
  let line = input.view(start_offset=0, end_offset=line_end).to_string()

  // Parse flags
  let var_names : Array[String] = []
  let mut prompt = ""
  let mut array_name : String? = None
  let mut i = 0
  while i < args.length() {
    if args[i] == "-p" && i + 1 < args.length() {
      prompt = args[i + 1]
      i += 2
    } else if args[i] == "-a" && i + 1 < args.length() {
      array_name = Some(args[i + 1])
      i += 2
    } else if args[i] == "-r" {
      i += 1
    } else {
      var_names.push(args[i])
      i += 1
    }
  }
  if prompt.length() > 0 {
    self.stderr_buf.write_string(prompt)
  }

  if var_names.length() == 0 {
    var_names.push("REPLY")
  }

  // Split line by current IFS and assign.
  let words = self.word_split(line)
  match array_name {
    Some(name) => {
      if words.length() > self.limits.max_array_elements {
        self.stderr_buf.write_string("read: array element limit exceeded\n")
        self.exit_code = 1
        return
      }
      self.store_array_assignment(name, words)
    }
    None => {
      for j = 0; j < var_names.length(); j = j + 1 {
        if j < var_names.length() - 1 {
          // Not the last variable - assign one word
          let value = if j < words.length() { words[j] } else { "" }
          self.env[var_names[j]] = value
        } else {
          // Last variable - assign rest of line
          if j < words.length() {
            let buf = StringBuilder::new()
            for k = j; k < words.length(); k = k + 1 {
              if k > j {
                buf.write_string(" ")
              }
              buf.write_string(words[k])
            }
            self.env[var_names[j]] = buf.to_string()
          } else {
            self.env[var_names[j]] = ""
          }
        }
      }
    }
  }

  // Consume the line from stdin
  if line_end < input.length() {
    self.stdin_buf = input.view(start_offset=line_end + 1).to_string()
  } else {
    self.stdin_buf = ""
  }

  self.exit_code = if input.length() == 0 { 1 } else { 0 }
}

fn ExecContext::builtin_mapfile(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut strip_newline = false
  let mut array_name = "MAPFILE"
  let mut i = 0

  while i < args.length() {
    let arg = args[i]
    if arg == "-t" {
      strip_newline = true
      i += 1
      continue
    }
    if arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      // Ignore unsupported flags for now.
      i += 1
      continue
    }
    array_name = arg
    i += 1
  }

  let lines = mapfile_split_lines(self.stdin_buf, strip_newline)
  if lines.length() > self.limits.max_array_elements {
    self.stderr_buf.write_string("mapfile: array element limit exceeded\n")
    self.exit_code = 1
    return
  }

  // Remove previous values for this array name.
  let remove_keys : Array[String] = []
  let index_prefix = array_name + "["
  let count_key = array_count_storage_key(array_name)
  for key, _value in self.env {
    if key == count_key || mapfile_starts_with(key, index_prefix) {
      remove_keys.push(key)
    }
  }
  for key in remove_keys {
    self.env.remove(key)
  }

  let joined = StringBuilder::new()
  for idx = 0; idx < lines.length(); idx = idx + 1 {
    let value = lines[idx]
    self.env["\{array_name}[\{idx.to_string()}]"] = value
    if idx > 0 {
      joined.write_char(' ')
    }
    joined.write_string(value)
  }
  self.env[array_name + "[@]"] = joined.to_string()
  self.env[array_name + "[*]"] = joined.to_string()
  self.env[count_key] = lines.length().to_string()
  self.exit_code = 0
}

fn mapfile_split_lines(input : String, strip_newline : Bool) -> Array[String] {
  let lines : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      let line = if strip_newline { buf.to_string() } else { buf.to_string() + "\n" }
      lines.push(line)
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    lines.push(remaining)
  }
  lines
}

fn mapfile_starts_with(s : String, prefix : String) -> Bool {
  if prefix.length() > s.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

fn array_count_storage_key(name : String) -> String {
  "__MOON_BASH_ARRAY_COUNT__" + name
}

fn ExecContext::builtin_test(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // Remove trailing ] if command was [
  let test_args = if args.length() > 0 && args[args.length() - 1] == "]" {
    let a : Array[String] = []
    for i = 0; i < args.length() - 1; i = i + 1 {
      a.push(args[i])
    }
    a
  } else {
    args
  }

  self.exit_code = if evaluate_test(test_args, self) { 0 } else { 1 }
}

fn ExecContext::builtin_double_bracket(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  // Mirror [[ ... ]] minimal semantics through the same evaluator.
  let test_args = if args.length() > 0 && args[args.length() - 1] == "]]" {
    let a : Array[String] = []
    for i = 0; i < args.length() - 1; i = i + 1 {
      a.push(args[i])
    }
    a
  } else {
    args
  }
  self.exit_code = if evaluate_test(test_args, self) { 0 } else { 1 }
}

fn ExecContext::builtin_printf(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("printf: usage: printf format [arguments]\n")
    self.exit_code = 1
    return
  }

  let mut value_target : String? = None
  let mut format_idx = 0
  if args.length() >= 2 && args[0] == "-v" {
    value_target = Some(args[1])
    format_idx = 2
  }
  if format_idx >= args.length() {
    self.stderr_buf.write_string("printf: usage: printf format [arguments]\n")
    self.exit_code = 1
    return
  }

  let format = args[format_idx]
  let fmt_args : Array[String] = []
  for i = format_idx + 1; i < args.length(); i = i + 1 {
    fmt_args.push(args[i])
  }
  let result = format_printf(format, fmt_args)
  match value_target {
    Some(name) => {
      if not(self.store_scalar_assignment(name, result)) {
        return
      }
    }
    None => self.stdout_buf.write_string(result)
  }
  self.exit_code = 0
}

fn ExecContext::builtin_eval(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 0
    return
  }
  let script = args.iter().fold(
    init="",
    fn(acc, a) { if acc.length() == 0 { a } else { acc + " " + a } },
  )
  let parsed = try {
    @parser.parse(script)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moon_bash: eval: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
}

fn ExecContext::builtin_let(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 1
    return
  }

  let mut last = 0L
  for expr_text in args {
    last = self.eval_arith(@ast.ArithExpr::Raw(expr_text))
  }
  self.exit_code = if last != 0L { 0 } else { 1 }
}

fn ExecContext::builtin_source(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.stderr_buf.write_string("moon_bash: source: filename argument required\n")
    self.exit_code = 2
    return
  }
  let path = try {
    @fs.resolve_path(self.cwd, args[0])
  } catch {
    _ => args[0]
  }
  let content = try {
    self.fs.read_file(path)
  } catch {
    @fs.FsError(msg) => {
      self.stderr_buf.write_string("moon_bash: source: \{msg}\n")
      self.exit_code = 1
      return
    }
  }
  let parsed = try {
    @parser.parse(content)
  } catch {
    @ast.BashError(msg) => {
      self.stderr_buf.write_string("moon_bash: source: \{msg}\n")
      self.exit_code = 2
      return
    }
  }
  self.execute_script(parsed)
}

fn ExecContext::builtin_type(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut opt_a = false
  let mut opt_t = false
  let mut opt_p = false
  let mut opt_upper_p = false
  let mut opt_f = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--" {
      i += 1
      break
    }
    if arg.length() >= 2 && arg[0].to_int().unsafe_to_char() == '-' {
      let mut recognized = true
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'a' => opt_a = true
          't' => opt_t = true
          'p' => opt_p = true
          'P' => opt_upper_p = true
          'f' => opt_f = true
          _ => recognized = false
        }
      }
      if recognized {
        i += 1
        continue
      }
    }
    break
  }

  if i >= args.length() {
    self.exit_code = 1
    return
  }

  let mut all_found = true
  let file_only_mode = opt_p || opt_upper_p

  for idx = i; idx < args.length(); idx = idx + 1 {
    let name = args[idx]
    if name.length() == 0 {
      all_found = false
      continue
    }

    if opt_t {
      let mut found = false
      if self.lookup_alias_value(name) is Some(_) {
        self.stdout_buf.write_string("alias\n")
        found = true
      } else if not(opt_f) && self.functions.contains(name) {
        self.stdout_buf.write_string("function\n")
        found = true
      } else if is_lookup_shell_keyword(name) {
        self.stdout_buf.write_string("keyword\n")
        found = true
      } else if is_lookup_shell_builtin(name) {
        self.stdout_buf.write_string("builtin\n")
        found = true
      } else {
        match self.first_path_command_match(name, false, true) {
          Some((_display, _resolved, _is_virtual)) => {
            self.stdout_buf.write_string("file\n")
            found = true
          }
          None => ()
        }
      }
      if not(found) {
        all_found = false
      }
      continue
    }

    if file_only_mode {
      if type_builtin_without_external_path(name) {
        all_found = false
        continue
      }

      let force_path_lookup = opt_upper_p || opt_a
      if not(force_path_lookup) {
        let shadowed_by_non_file = self.lookup_alias_value(name) is Some(_) ||
          (not(opt_f) && self.functions.contains(name)) ||
          is_lookup_shell_keyword(name) ||
          is_lookup_shell_builtin(name)
        if shadowed_by_non_file {
          all_found = false
          continue
        }
      }

      let matches = self.all_path_command_matches(name, false, true)
      let mut found = false
      if opt_a {
        for match_item in matches {
          let (display, _resolved, _is_virtual) = match_item
          self.stdout_buf.write_string(display + "\n")
          found = true
        }
      } else {
        if matches.length() > 0 {
          let (display, _resolved, _is_virtual) = matches[0]
          self.stdout_buf.write_string(display + "\n")
          found = true
        }
      }
      if not(found) {
        all_found = false
      }
      continue
    }

    if opt_a {
      let mut found = false
      match self.lookup_alias_value(name) {
        Some(alias_value) => {
          self.stdout_buf.write_string(
            "\{name} is an alias for \"\{alias_value}\"\n",
          )
          found = true
        }
        None => ()
      }
      if not(opt_f) {
        match self.functions.get(name) {
          Some(fndef) => {
            self.print_type_function_definition(name, fndef)
            found = true
          }
          None => ()
        }
      }
      if is_lookup_shell_keyword(name) {
        self.stdout_buf.write_string("\{name} is a shell keyword\n")
        found = true
      }
      if is_lookup_shell_builtin(name) {
        let builtin_kind = if is_special_shell_builtin(name) {
          "special shell builtin"
        } else {
          "shell builtin"
        }
        self.stdout_buf.write_string("\{name} is a \{builtin_kind}\n")
        found = true
      }
      if not(type_builtin_without_external_path(name)) {
        for match_item in self.all_path_command_matches(
          name,
          false,
          true,
        ) {
          let (display, _resolved, _is_virtual) = match_item
          self.stdout_buf.write_string("\{name} is \{display}\n")
          found = true
        }
      }
      if not(found) {
        self.stderr_buf.write_string("\{name}: not found\n")
        all_found = false
      }
      continue
    }

    match self.lookup_alias_value(name) {
      Some(alias_value) => {
        self.stdout_buf.write_string(
          "\{name} is an alias for \"\{alias_value}\"\n",
        )
        continue
      }
      None => ()
    }

    if not(opt_f) {
      match self.functions.get(name) {
        Some(fndef) => {
          self.print_type_function_definition(name, fndef)
          continue
        }
        None => ()
      }
    }

    if is_lookup_shell_keyword(name) {
      self.stdout_buf.write_string("\{name} is a shell keyword\n")
      continue
    }

    if is_lookup_shell_builtin(name) {
      let builtin_kind = if is_special_shell_builtin(name) {
        "special shell builtin"
      } else {
        "shell builtin"
      }
      self.stdout_buf.write_string("\{name} is a \{builtin_kind}\n")
      continue
    }

    match self.first_path_command_match(name, false, true) {
      Some((display, _resolved, _is_virtual)) => {
        self.stdout_buf.write_string("\{name} is \{display}\n")
      }
      None => {
        self.stderr_buf.write_string("\{name}: not found\n")
        all_found = false
      }
    }
  }
  self.exit_code = if all_found { 0 } else { 1 }
}

fn ExecContext::builtin_command(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() == 0 {
    self.exit_code = 0
    return
  }

  let mut mode = 0
  // 0: exec, 1: -v, 2: -V
  let mut use_default_path = false

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--" {
      i += 1
      break
    }
    if arg.length() >= 2 && arg[0].to_int().unsafe_to_char() == '-' {
      let mut recognized = true
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        match flag {
          'v' => mode = 1
          'V' => mode = 2
          'p' => use_default_path = true
          _ => recognized = false
        }
      }
      if recognized {
        i += 1
        continue
      }
    }
    break
  }

  if i >= args.length() {
    self.exit_code = 0
    return
  }

  if mode == 1 {
    let mut all_found = true
    for idx = i; idx < args.length(); idx = idx + 1 {
      let name = args[idx]
      if name.length() == 0 {
        all_found = false
        continue
      }
      if self.lookup_alias_value(name) is Some(_) {
        self.stdout_buf.write_string(name + "\n")
        continue
      }
      if self.functions.contains(name) {
        self.stdout_buf.write_string(name + "\n")
        continue
      }
      if is_lookup_shell_builtin(name) {
        self.stdout_buf.write_string(name + "\n")
        continue
      }
      if is_lookup_shell_keyword(name) {
        self.stdout_buf.write_string(name + "\n")
        continue
      }
      match self.first_path_command_match(name, use_default_path, true) {
        Some((display, _resolved, _is_virtual)) => {
          self.stdout_buf.write_string(display + "\n")
        }
        None => all_found = false
      }
    }
    self.exit_code = if all_found { 0 } else { 1 }
    return
  }

  if mode == 2 {
    let mut all_found = true
    for idx = i; idx < args.length(); idx = idx + 1 {
      let name = args[idx]
      if name.length() == 0 {
        self.stderr_buf.write_string(": not found\n")
        all_found = false
        continue
      }
      match self.lookup_alias_value(name) {
        Some(alias_value) => {
          self.stdout_buf.write_string(
            "\{name} is an alias for \"\{alias_value}\"\n",
          )
          continue
        }
        None => ()
      }
      if self.functions.contains(name) {
        self.stdout_buf.write_string("\{name} is a function\n")
        continue
      }
      if is_lookup_shell_builtin(name) {
        self.stdout_buf.write_string("\{name} is a shell builtin\n")
        continue
      }
      if is_lookup_shell_keyword(name) {
        self.stdout_buf.write_string("\{name} is a shell keyword\n")
        continue
      }
      match self.first_path_command_match(name, use_default_path, true) {
        Some((display, _resolved, _is_virtual)) => {
          self.stdout_buf.write_string("\{name} is \{display}\n")
        }
        None => {
          self.stderr_buf.write_string("\{name}: not found\n")
          all_found = false
        }
      }
    }
    self.exit_code = if all_found { 0 } else { 1 }
    return
  }

  let cmd_name = args[i]
  let cmd_args : Array[String] = []
  for idx = i + 1; idx < args.length(); idx = idx + 1 {
    cmd_args.push(args[idx])
  }

  let saved_skip = self.env.get(command_skip_function_lookup_key)
  let saved_default = self.env.get(command_default_path_lookup_key)
  self.env[command_skip_function_lookup_key] = "1"
  if use_default_path {
    self.env[command_default_path_lookup_key] = "1"
  } else {
    self.env.remove(command_default_path_lookup_key)
  }
  self.run_command(cmd_name, cmd_args)
  match saved_skip {
    Some(value) => self.env[command_skip_function_lookup_key] = value
    None => self.env.remove(command_skip_function_lookup_key)
  }
  match saved_default {
    Some(value) => self.env[command_default_path_lookup_key] = value
    None => self.env.remove(command_default_path_lookup_key)
  }
}

fn type_word_part_to_text(part : @ast.WordPart) -> String {
  match part {
    @ast.WordPart::Literal(text) => text
    @ast.WordPart::SingleQuoted(text) => text
    @ast.WordPart::DoubleQuoted(parts) => {
      let buf = StringBuilder::new()
      for inner in parts {
        buf.write_string(type_word_part_to_text(inner))
      }
      buf.to_string()
    }
    @ast.WordPart::Variable(name) => "$" + name
    @ast.WordPart::ParameterExpansion(_) => ""
    @ast.WordPart::CommandSubstitution(_) => ""
    @ast.WordPart::ArithmeticExpansion(_) => ""
    @ast.WordPart::BraceExpansion(_) => ""
    @ast.WordPart::TildePrefix(prefix) => "~" + prefix
    @ast.WordPart::Glob(pattern) => pattern.pattern
  }
}

fn type_word_to_text(word : @ast.Word) -> String {
  let buf = StringBuilder::new()
  for part in word.parts {
    buf.write_string(type_word_part_to_text(part))
  }
  buf.to_string()
}

fn type_render_simple_command(simple : @ast.SimpleCommand) -> String {
  let pieces : Array[String] = []
  for assign in simple.assignments {
    match assign.value {
      Some(value_word) => {
        let value = type_word_to_text(value_word)
        if assign.append {
          pieces.push("\{assign.name}+=\{value}")
        } else {
          pieces.push("\{assign.name}=\{value}")
        }
      }
      None => {
        if assign.append {
          pieces.push(assign.name + "+=")
        } else {
          pieces.push(assign.name + "=")
        }
      }
    }
  }
  for word in simple.words {
    pieces.push(type_word_to_text(word))
  }
  if pieces.length() == 0 {
    return ""
  }
  pieces.iter().fold(
    init="",
    fn(acc, piece) { if acc.length() == 0 { piece } else { acc + " " + piece } },
  )
}

fn type_collect_pipeline_line(
  pipeline : @ast.Pipeline,
  lines : Array[String]
) -> Unit {
  if pipeline.commands.length() == 0 {
    return
  }
  if pipeline.commands.length() > 1 {
    return
  }
  match pipeline.commands[0] {
    @ast.Command::Simple(simple) => {
      let rendered = type_render_simple_command(simple)
      if rendered.length() > 0 {
        lines.push(rendered)
      }
    }
    _ => ()
  }
}

fn type_collect_statement_lines(
  stmt : @ast.Statement,
  lines : Array[String]
) -> Unit {
  match stmt {
    @ast.Statement::Pipeline(pipeline) => type_collect_pipeline_line(pipeline, lines)
    @ast.Statement::Sequence(pipeline, right) => {
      type_collect_pipeline_line(pipeline, lines)
      type_collect_statement_lines(right, lines)
    }
    @ast.Statement::AndList(pipeline, right) => {
      type_collect_pipeline_line(pipeline, lines)
      type_collect_statement_lines(right, lines)
    }
    @ast.Statement::OrList(pipeline, right) => {
      type_collect_pipeline_line(pipeline, lines)
      type_collect_statement_lines(right, lines)
    }
    @ast.Statement::Background(pipeline) => type_collect_pipeline_line(pipeline, lines)
  }
}

fn type_render_function_body_lines(body : @ast.CompoundCommand) -> Array[String] {
  let lines : Array[String] = []
  match body {
    @ast.CompoundCommand::Group(script) => {
      for stmt in script.statements {
        type_collect_statement_lines(stmt, lines)
      }
    }
    _ => ()
  }
  lines
}

fn ExecContext::print_type_function_definition(
  self : ExecContext,
  name : String,
  fndef : @ast.FunctionDef
) -> Unit {
  self.stdout_buf.write_string("\{name} is a function\n")
  self.stdout_buf.write_string("\{name} () \n")
  self.stdout_buf.write_string("{ \n")
  let lines = type_render_function_body_lines(fndef.body)
  if lines.length() == 0 {
    self.stdout_buf.write_string("    :\n")
  } else {
    for line in lines {
      self.stdout_buf.write_string("    \{line}\n")
    }
  }
  self.stdout_buf.write_string("}\n")
}

fn type_builtin_without_external_path(name : String) -> Bool {
  match name {
    "cd" | "type" | "builtin" | "command" => true
    _ => false
  }
}
