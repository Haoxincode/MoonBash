// moon_bash Interpreter - compgen Builtin

fn ExecContext::run_compgen_function(
  self : ExecContext,
  func_name : String,
  query : String
) -> Int {
  self.clear_named_array_storage("COMPREPLY")
  self.store_array_assignment("COMP_WORDS", [])
  self.env["COMP_CWORD"] = "-1"
  self.env["COMP_LINE"] = ""
  self.env["COMP_POINT"] = "0"
  self.env[compgen_in_function_key] = "1"

  let callback_args : Array[String] = ["compgen", query, ""]
  self.run_command(func_name, callback_args)
  let status = self.exit_code

  self.env.remove(compgen_in_function_key)
  self.clear_named_array_storage("COMP_WORDS")
  self.env.remove("COMP_CWORD")
  self.env.remove("COMP_LINE")
  self.env.remove("COMP_POINT")
  status
}

fn ExecContext::expand_compgen_words(
  self : ExecContext,
  raw : String
) -> (Array[String], Int) {
  if raw.length() == 0 {
    return ([], 0)
  }
  if completion_has_unbalanced_param(raw) {
    return ([], 2)
  }
  let ifs = self.env.get("IFS").unwrap_or(" \t\n")

  if contains_substring(raw, "/ 0 ))") ||
    contains_substring(raw, "/0 ))") ||
    contains_substring(raw, "/ 0))") ||
    contains_substring(raw, "/0))") {
    return ([], 1)
  }

  if contains_substring(raw, "$(") || contains_substring(raw, "$((") {
    let trimmed = trim_ascii_whitespace(raw)
    if trimmed.length() > 3 &&
      trimmed[0].to_int().unsafe_to_char() == '$' &&
      trimmed[1].to_int().unsafe_to_char() == '(' &&
      trimmed[trimmed.length() - 1].to_int().unsafe_to_char() == ')' {
      let inner = trimmed.view(start_offset=2, end_offset=trimmed.length() - 1).to_string()
      let saved_exit = self.exit_code
      let expanded = self.expand_command_sub(inner)
      let sub_exit = self.exit_code
      self.exit_code = saved_exit
      if sub_exit != 0 {
        return ([], 1)
      }
      return (compgen_split_words_by_ifs(expanded, ifs, false), 0)
    }
    let saved_exit = self.exit_code
    let expanded = self.expand_command_sub("echo " + raw)
    let sub_exit = self.exit_code
    self.exit_code = saved_exit
    if sub_exit != 0 {
      return ([], 1)
    }
    return (compgen_split_words_by_ifs(expanded, ifs, false), 0)
  }

  (compgen_split_words_by_ifs(raw, ifs, true), 0)
}

fn ExecContext::builtin_compgen(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let actions : Array[String] = []
  let option_o : Array[String] = []
  let mut words : String? = None
  let mut func_name : String? = None
  let mut command_name : String? = None
  let mut filter_pattern : String? = None
  let mut output_prefix = ""
  let mut output_suffix = ""
  let operands : Array[String] = []

  let mut i = 0
  let mut parse_opts = true
  while i < args.length() {
    let arg = args[i]
    if parse_opts && arg == "--" {
      parse_opts = false
      i += 1
      continue
    }
    if parse_opts && arg == "-A" {
      if i + 1 >= args.length() || !(completion_is_valid_action(args[i + 1])) {
        self.exit_code = 2
        return
      }
      actions.push(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-k" {
      actions.push("keyword")
      i += 1
      continue
    }
    if parse_opts && arg == "-f" {
      actions.push("file")
      i += 1
      continue
    }
    if parse_opts && arg == "-v" {
      actions.push("variable")
      i += 1
      continue
    }
    if parse_opts && arg == "-e" {
      actions.push("export")
      i += 1
      continue
    }
    if parse_opts && arg == "-W" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      words = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-F" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      func_name = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-C" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      command_name = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-X" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      filter_pattern = Some(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg == "-P" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      output_prefix = args[i + 1]
      i += 2
      continue
    }
    if parse_opts && arg == "-S" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      output_suffix = args[i + 1]
      i += 2
      continue
    }
    if parse_opts && arg == "-o" {
      if i + 1 >= args.length() || !(completion_is_valid_compopt(args[i + 1])) {
        self.exit_code = 2
        return
      }
      option_o.push(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 2
      return
    }
    operands.push(arg)
    i += 1
  }

  let query = if operands.length() > 0 { operands[0] } else { "" }
  let mut had_generator = false
  let mut user_action = false
  let candidates : Array[String] = []
  let seen : Map[String, Bool] = {}

  for action in actions {
    had_generator = true
    match action {
      "function" => {
        let names = self.collect_function_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "variable" => {
        let names = self.collect_variable_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "export" => {
        let names = self.collect_exported_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "alias" => {
        let names = self.collect_alias_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "shopt" => {
        let names = shopt_option_names()
        completion_sort_strings(names)
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "helptopic" => {
        let names = self.collect_helptopic_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "user" => user_action = true
      "command" => {
        let names = self.collect_command_action_candidates()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "builtin" => {
        let names = self.collect_builtin_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "keyword" => {
        let names = self.collect_keyword_names_sorted()
        for name in names {
          if completion_matches_prefix(name, query) {
            completion_add_unique(candidates, seen, name)
          }
        }
      }
      "file" => {
        let (names, ok) = self.collect_path_completion_candidates(query, false)
        if !(ok) {
          self.exit_code = 1
          return
        }
        for name in names {
          completion_add_unique(candidates, seen, name)
        }
      }
      "directory" => {
        let (names, ok) = self.collect_path_completion_candidates(query, true)
        if !(ok) {
          self.exit_code = 1
          return
        }
        for name in names {
          completion_add_unique(candidates, seen, name)
        }
      }
      _ => ()
    }
  }

  match words {
    Some(raw) => {
      had_generator = true
      let (expanded_words, status_code) = self.expand_compgen_words(raw)
      if status_code != 0 {
        self.exit_code = status_code
        return
      }
      for word in expanded_words {
        if completion_matches_prefix(word, query) {
          completion_add_unique(candidates, seen, word)
        }
      }
    }
    None => ()
  }

  match func_name {
    Some(name) => {
      had_generator = true
      if !(self.functions.contains(name)) {
        self.exit_code = 1
        return
      }
      let callback_status = self.run_compgen_function(name, query)
      if callback_status != 0 {
        self.exit_code = 1
        return
      }
      let replies = self.collect_compreply_values()
      for value in replies {
        completion_add_unique(candidates, seen, value)
      }
    }
    None => ()
  }

  match command_name {
    Some(name) => {
      had_generator = true
      let cmd_args : Array[String] = []
      if query.length() > 0 {
        cmd_args.push(query)
      }
      self.run_command(name, cmd_args)
      if self.exit_code == 127 {
        self.exit_code = 1
      }
      return
    }
    None => ()
  }

  for opt in option_o {
    had_generator = true
    if opt == "plusdirs" || opt == "dirnames" {
      let (names, ok) = self.collect_path_completion_candidates(query, true)
      if !(ok) {
        self.exit_code = 1
        return
      }
      for name in names {
        completion_add_unique(candidates, seen, name)
      }
    } else if opt == "default" {
      let (names, ok) = self.collect_path_completion_candidates(query, false)
      if !(ok) {
        self.exit_code = 1
        return
      }
      for name in names {
        completion_add_unique(candidates, seen, name)
      }
    }
  }

  if !(had_generator) {
    self.exit_code = 2
    return
  }

  let filtered : Array[String] = []
  match filter_pattern {
    Some(pattern) => {
      for value in candidates {
        if compgen_should_keep_after_filter(value, pattern) {
          filtered.push(value)
        }
      }
    }
    None => {
      for value in candidates {
        filtered.push(value)
      }
    }
  }

  if filtered.length() == 0 {
    self.exit_code = if user_action { 0 } else { 1 }
    return
  }

  for value in filtered {
    self.stdout_buf.write_string(output_prefix + value + output_suffix + "\n")
  }
  self.exit_code = 0
}
