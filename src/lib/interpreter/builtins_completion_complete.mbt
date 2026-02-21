// moon_bash Interpreter - complete, compopt Builtins and Completion Helpers

fn ExecContext::collect_completion_names(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for key, _value in self.env {
    if key.has_prefix(complete_storage_prefix) {
      names.push(complete_storage_name_from_key(key))
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::print_completion_specs(
  self : ExecContext,
  names : Array[String]
) -> Unit {
  if names.length() == 0 {
    let all_names = self.collect_completion_names()
    for name in all_names {
      match self.env.get(complete_storage_key(name)) {
        Some(spec) => self.stdout_buf.write_string(spec + "\n")
        None => ()
      }
    }
    return
  }

  for name in names {
    match self.env.get(complete_storage_key(name)) {
      Some(spec) => self.stdout_buf.write_string(spec + "\n")
      None => ()
    }
  }
}

fn ExecContext::builtin_complete(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut print_mode = false
  let mut words : String? = None
  let mut func_name : String? = None
  let mut command_name : String? = None
  let complete_opts : Array[String] = []
  let names : Array[String] = []

  let mut i = 0
  let mut parse_opts = true
  while i < args.length() {
    let arg = args[i]
    if parse_opts && arg == "--" {
      parse_opts = false
      i += 1
      continue
    }
    if parse_opts && arg == "-p" {
      print_mode = true
      i += 1
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
    if parse_opts && arg == "-W" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      words = Some(args[i + 1])
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
    if parse_opts && arg == "-o" {
      if i + 1 >= args.length() {
        self.exit_code = 2
        return
      }
      complete_opts.push(args[i + 1])
      i += 2
      continue
    }
    if parse_opts && arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '-' {
      self.exit_code = 2
      return
    }
    names.push(arg)
    i += 1
  }

  if print_mode &&
    words is None &&
    func_name is None &&
    command_name is None &&
    names.length() == 0 {
    self.print_completion_specs([])
    self.exit_code = 0
    return
  }

  if words is None && func_name is None && command_name is None {
    if print_mode {
      self.print_completion_specs(names)
      self.exit_code = 0
      return
    }
    if names.length() == 0 {
      self.print_completion_specs([])
      self.exit_code = 0
      return
    }
    self.exit_code = 2
    return
  }

  if names.length() == 0 {
    self.exit_code = 2
    return
  }

  match words {
    Some(raw) => {
      if completion_has_unbalanced_param(raw) {
        self.exit_code = 2
        return
      }
    }
    None => ()
  }

  match func_name {
    Some(name) => {
      if not(self.functions.contains(name)) {
        for target in names {
          if target == "-D" {
            self.exit_code = 2
            return
          }
        }
      }
    }
    None => ()
  }

  let spec_tokens : Array[String] = ["complete"]
  for opt in complete_opts {
    spec_tokens.push("-o")
    spec_tokens.push(opt)
  }
  match words {
    Some(raw) => {
      spec_tokens.push("-W")
      spec_tokens.push("'" + raw + "'")
    }
    None => ()
  }
  match func_name {
    Some(name) => {
      spec_tokens.push("-F")
      spec_tokens.push(name)
    }
    None => ()
  }
  match command_name {
    Some(name) => {
      spec_tokens.push("-C")
      spec_tokens.push(name)
    }
    None => ()
  }
  let spec_head = completion_join_words(spec_tokens)

  for name in names {
    self.env[complete_storage_key(name)] = spec_head + " " + name
  }
  self.exit_code = 0
}

fn ExecContext::builtin_compopt(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut has_action = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--" {
      break
    }
    if arg == "-o" || arg == "+o" {
      if i + 1 >= args.length() || not(completion_is_valid_compopt(args[i + 1])) {
        self.exit_code = 2
        return
      }
      has_action = true
      i += 2
      continue
    }
    if arg.length() > 0 {
      let first = arg[0].to_int().unsafe_to_char()
      if first == '-' || first == '+' {
        self.exit_code = 2
        return
      }
    }
    i += 1
  }

  if not(has_action) {
    self.exit_code = 2
    return
  }
  if self.env.get(compgen_in_function_key).unwrap_or("") != "1" {
    self.exit_code = 1
    return
  }
  self.exit_code = 0
}

fn ExecContext::collect_function_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for name, _fndef in self.functions {
    if is_valid_shell_name(name) {
      names.push(name)
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_alias_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for key, _value in self.env {
    if key.has_prefix(completion_alias_prefix) {
      names.push(key.view(start_offset=completion_alias_prefix.length()).to_string())
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_variable_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  let seen : Map[String, Bool] = {}
  for key, _value in self.env {
    if key.has_prefix("__") {
      continue
    }
    let base = completion_variable_base_name(key)
    if not(is_valid_shell_name(base)) {
      continue
    }
    if seen.contains(base) {
      continue
    }
    seen[base] = true
    names.push(base)
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_exported_names_sorted(self : ExecContext) -> Array[String] {
  let names : Array[String] = []
  for name, exported in self.exported {
    if exported && is_valid_shell_name(name) {
      names.push(name)
    }
  }
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_builtin_names_sorted(self : ExecContext) -> Array[String] {
  ignore(self)
  let names = compgen_builtin_names()
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_keyword_names_sorted(self : ExecContext) -> Array[String] {
  ignore(self)
  let names = shell_keyword_names()
  completion_sort_strings(names)
  names
}

fn ExecContext::collect_helptopic_names_sorted(self : ExecContext) -> Array[String] {
  ignore(self)
  let topics : Array[String] = []
  let seen : Map[String, Bool] = {}
  for name in builtin_candidate_names() {
    completion_add_unique(topics, seen, name)
  }
  for name in shell_keyword_names() {
    completion_add_unique(topics, seen, name)
  }
  for name in registry_command_names() {
    completion_add_unique(topics, seen, name)
  }
  completion_sort_strings(topics)
  topics
}

fn ExecContext::collect_command_action_candidates(self : ExecContext) -> Array[String] {
  let out : Array[String] = []
  let seen : Map[String, Bool] = {}

  let aliases = self.collect_alias_names_sorted()
  for name in aliases {
    completion_add_unique(out, seen, name)
  }

  let functions = self.collect_function_names_sorted()
  for name in functions {
    completion_add_unique(out, seen, name)
  }

  let builtins = self.collect_builtin_names_sorted()
  for name in builtins {
    completion_add_unique(out, seen, name)
  }

  let keywords = self.collect_keyword_names_sorted()
  for name in keywords {
    completion_add_unique(out, seen, name)
  }

  let registry = registry_command_names()
  let sorted_registry : Array[String] = []
  for name in registry {
    sorted_registry.push(name)
  }
  completion_sort_strings(sorted_registry)
  for name in sorted_registry {
    completion_add_unique(out, seen, name)
  }

  out
}

fn ExecContext::collect_path_completion_candidates(
  self : ExecContext,
  query : String,
  directories_only : Bool
) -> (Array[String], Bool) {
  let mut dir_part = ""
  let mut name_prefix = query
  let mut output_prefix = ""
  let slash_idx = completion_last_slash(query)
  if slash_idx >= 0 {
    dir_part = if slash_idx == 0 {
      "/"
    } else {
      query.view(start_offset=0, end_offset=slash_idx).to_string()
    }
    name_prefix = if slash_idx + 1 < query.length() {
      query.view(start_offset=slash_idx + 1).to_string()
    } else {
      ""
    }
    output_prefix = query.view(start_offset=0, end_offset=slash_idx + 1).to_string()
  }

  let base_dir = if dir_part.length() == 0 {
    self.cwd
  } else {
    try {
      @fs.resolve_path(self.cwd, dir_part)
    } catch {
      _ => return ([], false)
    }
  }

  match self.fs.entries.get(base_dir) {
    Some(@fs.FsEntry::Directory(_)) => ()
    _ => return ([], false)
  }

  let out : Array[String] = []
  for path, entry in self.fs.entries {
    if @fs.parent_path(path) != base_dir {
      continue
    }
    let name = @fs.basename(path)
    if not(name.has_prefix(name_prefix)) {
      continue
    }
    match entry {
      @fs.FsEntry::Directory(_) => out.push(output_prefix + name)
      _ => {
        if not(directories_only) {
          out.push(output_prefix + name)
        }
      }
    }
  }
  completion_sort_strings(out)
  (out, true)
}

fn ExecContext::clear_named_array_storage(
  self : ExecContext,
  name : String
) -> Unit {
  let count_key = "__MOON_BASH_ARRAY_COUNT__" + name
  let index_prefix = name + "["
  let to_remove : Array[String] = []
  for key, _value in self.env {
    if key == name ||
      key == count_key ||
      key == name + "[@]" ||
      key == name + "[*]" ||
      string_has_prefix(key, index_prefix) {
      to_remove.push(key)
    }
  }
  for key in to_remove {
    self.env.remove(key)
  }
}

fn ExecContext::collect_compreply_values(self : ExecContext) -> Array[String] {
  let values = self.collect_array_values("COMPREPLY")
  if values.length() > 0 {
    return values
  }
  match self.env.get("COMPREPLY") {
    Some(value) => {
      if value.length() == 0 {
        []
      } else {
        [value]
      }
    }
    None => []
  }
}
