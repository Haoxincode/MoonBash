// moon_bash Interpreter - Builtins (State and Flow)
// Split from builtins_core.mbt for maintainability.

fn ExecContext::builtin_export(self : ExecContext, args : Array[String]) -> Unit {
  if args.length() == 0 {
    // List exported vars
    for k, _v in self.exported {
      let value = self.env.get(k).unwrap_or("")
      self.stdout_buf.write_string("declare -x \{k}=\"\{value}\"\n")
    }
    self.exit_code = 0
    return
  }
  for arg in args {
    // Check for name=value
    let mut eq_pos = -1
    for i = 0; i < arg.length(); i = i + 1 {
      if arg[i] == '=' {
        eq_pos = i
        break
      }
    }
    if eq_pos > 0 {
      let name = arg.view(start_offset=0, end_offset=eq_pos).to_string()
      let value = arg.view(start_offset=eq_pos + 1).to_string()
      self.env[name] = value
      self.exported[name] = true
    } else {
      self.exported[arg] = true
    }
  }
  self.exit_code = 0
}

fn ExecContext::builtin_unset(self : ExecContext, args : Array[String]) -> Unit {
  let mut unset_functions = false
  for arg in args {
    if arg == "-f" {
      unset_functions = true
      continue
    }
    if arg == "-v" {
      unset_functions = false
      continue
    }
    if unset_functions {
      self.functions.remove(arg)
      continue
    }
    self.env.remove(arg)
    self.env.remove("__MOON_BASH_NAMEREF__" + arg)
    self.env.remove(readonly_storage_key(arg))
    self.env.remove(integer_attr_storage_key(arg))
    self.env.remove(lower_attr_storage_key(arg))
    self.env.remove(upper_attr_storage_key(arg))
    self.exported.remove(arg)
  }
  self.exit_code = 0
}

fn ExecContext::builtin_set(self : ExecContext, args : Array[String]) -> Unit {
  if args.length() == 0 {
    // Print all variables
    for k, v in self.env {
      self.stdout_buf.write_string("\{k}=\{v}\n")
    }
    self.exit_code = 0
    return
  }
  let mut i = 0
  let mut positional_start = -1
  while i < args.length() {
    let arg = args[i]
    if arg == "--" {
      positional_start = i + 1
      break
    }
    if arg == "-o" {
      if i + 1 < args.length() {
        self.set_named_shell_option(args[i + 1], true)
        i += 2
      } else {
        i += 1
      }
      continue
    }
    if arg == "+o" {
      if i + 1 < args.length() {
        self.set_named_shell_option(args[i + 1], false)
        i += 2
      } else {
        i += 1
      }
      continue
    }
    if arg.length() >= 2 && arg[0] == '-' {
      let ch = arg.view(start_offset=1, end_offset=2).to_string()
      match ch {
        "e" => self.options.errexit = true
        "u" => self.options.nounset = true
        "f" => self.options.noglob = true
        "x" => self.options.xtrace = true
        "C" => self.options.noclobber = true
        "a" => self.options.allexport = true
        _ => ()
      }
      i += 1
    } else if arg.length() >= 2 && arg[0] == '+' {
      let ch = arg.view(start_offset=1, end_offset=2).to_string()
      match ch {
        "e" => self.options.errexit = false
        "u" => self.options.nounset = false
        "f" => self.options.noglob = false
        "x" => self.options.xtrace = false
        "C" => self.options.noclobber = false
        "a" => self.options.allexport = false
        _ => ()
      }
      i += 1
    } else {
      positional_start = i
      break
    }
  }

  if positional_start >= 0 {
    let values : Array[String] = []
    for j = positional_start; j < args.length(); j = j + 1 {
      values.push(args[j])
    }
    self.set_positional_parameters(values)
  }

  self.exit_code = 0
}

fn ExecContext::set_named_shell_option(
  self : ExecContext,
  name : String,
  enabled : Bool
) -> Unit {
  match name {
    "pipefail" => self.options.pipefail = enabled
    "errexit" => self.options.errexit = enabled
    "nounset" => self.options.nounset = enabled
    "noglob" => self.options.noglob = enabled
    "xtrace" => self.options.xtrace = enabled
    "noclobber" => self.options.noclobber = enabled
    "allexport" => self.options.allexport = enabled
    _ => ()
  }
}

fn ExecContext::set_positional_parameters(
  self : ExecContext,
  values : Array[String]
) -> Unit {
  let old_count = match self.env.get("#") {
    Some(s) => parse_int32_str(s)
    None => 0
  }
  for i = 1; i <= old_count; i = i + 1 {
    self.env.remove(i.to_string())
  }

  let joined = values.iter().fold(
    init="",
    fn(acc, value) { if acc.length() == 0 { value } else { acc + " " + value } },
  )
  self.env["@"] = joined
  self.env["#"] = values.length().to_string()
  for i = 0; i < values.length(); i = i + 1 {
    self.env[(i + 1).to_string()] = values[i]
  }
}

fn ExecContext::builtin_shift(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let n = if args.length() > 0 { parse_int32_str(args[0]) } else { 1 }
  let count = match self.env.get("#") {
    Some(s) => parse_int32_str(s)
    None => 0
  }
  if n > count {
    self.stderr_buf.write_string("moon_bash: shift: count exceeds positional parameters\n")
    self.exit_code = 1
    return
  }
  for i = 1; i <= count - n; i = i + 1 {
    let src_idx = i + n
    match self.env.get(src_idx.to_string()) {
      Some(v) => self.env[i.to_string()] = v
      None => ()
    }
  }
  for i = count - n + 1; i <= count; i = i + 1 {
    self.env.remove(i.to_string())
  }
  let remaining = count - n
  self.env["#"] = remaining.to_string()
  let values : Array[String] = []
  for i = 1; i <= remaining; i = i + 1 {
    values.push(self.env.get(i.to_string()).unwrap_or(""))
  }
  self.env["@"] = values.iter().fold(
    init="",
    fn(acc, value) { if acc.length() == 0 { value } else { acc + " " + value } },
  )
  self.exit_code = 0
}

fn ExecContext::builtin_exit(self : ExecContext, args : Array[String]) -> Unit {
  self.exit_code = if args.length() > 0 {
    parse_int32_str(args[0])
  } else {
    self.exit_code
  }
  self.should_exit = true
}

fn ExecContext::builtin_exec(self : ExecContext, args : Array[String]) -> Unit {
  if args.length() == 0 {
    self.exit_code = 0
    return
  }

  let command = args[0]
  let cmd_args : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    cmd_args.push(args[i])
  }
  self.run_command(command, cmd_args)
}

fn ExecContext::builtin_return(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if self.call_depth <= 0 {
    self.stderr_buf.write_string(
      "moon_bash: return: can only `return` from a function or sourced script\n",
    )
    self.exit_code = 1
    self.return_requested = false
    return
  }
  self.exit_code = if args.length() > 0 {
    parse_int32_str(args[0])
  } else {
    self.exit_code
  }
  self.return_requested = true
}

fn ExecContext::builtin_break(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let n = if args.length() > 0 { parse_int32_str(args[0]) } else { 1 }
  if self.loop_depth > 0 {
    self.break_count = n
  }
  self.exit_code = 0
}

fn ExecContext::builtin_continue(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let n = if args.length() > 0 { parse_int32_str(args[0]) } else { 1 }
  if self.loop_depth > 0 {
    self.continue_count = n
  }
  self.exit_code = 0
}

fn ExecContext::builtin_local(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  for arg in args {
    let mut eq_pos = -1
    for i = 0; i < arg.length(); i = i + 1 {
      if arg[i] == '=' {
        eq_pos = i
        break
      }
    }
    if eq_pos > 0 {
      let name = arg.view(start_offset=0, end_offset=eq_pos).to_string()
      let value = arg.view(start_offset=eq_pos + 1).to_string()
      self.capture_local_binding(name)
      self.env[name] = value
    } else {
      self.capture_local_binding(arg)
      if not(self.env.contains(arg)) {
        self.env[arg] = ""
      }
    }
  }
  self.exit_code = 0
}

fn ExecContext::capture_local_binding(self : ExecContext, name : String) -> Unit {
  if self.call_depth <= 0 {
    return
  }

  let depth = self.call_depth
  let names_key = local_scope_names_key(depth)
  let saved_set_key = local_scope_saved_set_key(depth, name)
  let saved_value_key = local_scope_saved_value_key(depth, name)
  if self.env.contains(saved_set_key) {
    return
  }

  match self.env.get(name) {
    Some(value) => {
      self.env[saved_set_key] = "1"
      self.env[saved_value_key] = value
    }
    None => self.env[saved_set_key] = "0"
  }

  let names = self.env.get(names_key).unwrap_or("")
  self.env[names_key] = if names.length() == 0 {
    name
  } else {
    names + "\u001f" + name
  }
}

fn ExecContext::restore_local_bindings(self : ExecContext, depth : Int) -> Unit {
  if depth <= 0 {
    return
  }

  let names_key = local_scope_names_key(depth)
  let names = self.env.get(names_key).unwrap_or("")
  if names.length() == 0 {
    self.env.remove(names_key)
    return
  }

  for name in split_local_scope_names(names) {
    let saved_set_key = local_scope_saved_set_key(depth, name)
    let saved_value_key = local_scope_saved_value_key(depth, name)
    match self.env.get(saved_set_key) {
      Some(flag) => {
        if flag == "1" {
          self.env[name] = self.env.get(saved_value_key).unwrap_or("")
        } else {
          self.env.remove(name)
        }
      }
      None => ()
    }
    self.env.remove(saved_set_key)
    self.env.remove(saved_value_key)
  }

  self.env.remove(names_key)
}

fn local_scope_names_key(depth : Int) -> String {
  "__MOON_BASH_LOCAL_NAMES__" + depth.to_string()
}

fn local_scope_saved_set_key(depth : Int, name : String) -> String {
  "__MOON_BASH_LOCAL_SET__" + depth.to_string() + "__" + name
}

fn local_scope_saved_value_key(depth : Int, name : String) -> String {
  "__MOON_BASH_LOCAL_VAL__" + depth.to_string() + "__" + name
}

fn split_local_scope_names(spec : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  for i = 0; i <= spec.length(); i = i + 1 {
    if i == spec.length() || spec[i].to_int().unsafe_to_char() == '\u001f' {
      if i > start {
        parts.push(spec.view(start_offset=start, end_offset=i).to_string())
      }
      start = i + 1
    }
  }
  parts
}

fn ExecContext::builtin_declare(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let mut nameref = false
  let mut print_mode = false
  let mut function_mode = false
  let mut readonly_mode = false
  let mut integer_mode = false
  let mut lowercase_mode = false
  let mut uppercase_mode = false
  let mut export_mode = false
  let filtered : Array[String] = []
  for arg in args {
    if arg.length() > 0 && arg[0] == '-' {
      if declare_flag_contains(arg, 'n') {
        nameref = true
      }
      if declare_flag_contains(arg, 'p') {
        print_mode = true
      }
      if declare_flag_contains(arg, 'f') {
        function_mode = true
      }
      if declare_flag_contains(arg, 'r') {
        readonly_mode = true
      }
      if declare_flag_contains(arg, 'i') {
        integer_mode = true
      }
      if declare_flag_contains(arg, 'l') {
        lowercase_mode = true
      }
      if declare_flag_contains(arg, 'u') {
        uppercase_mode = true
      }
      if declare_flag_contains(arg, 'x') {
        export_mode = true
      }
      continue
    }
    filtered.push(arg)
  }

  if print_mode {
    let mut failed = false
    if function_mode {
      if filtered.length() == 0 {
        for name, _f in self.functions {
          self.stdout_buf.write_string("\{name} ()\n")
        }
      } else {
        for name in filtered {
          if self.functions.contains(name) {
            self.stdout_buf.write_string("\{name} ()\n")
          } else {
            self.stderr_buf.write_string("moon_bash: declare: \{name}: not found\n")
            failed = true
          }
        }
      }
    } else {
      if filtered.length() == 0 {
        for name, value in self.env {
          self.stdout_buf.write_string("declare -- \{name}=\"\{value}\"\n")
        }
      } else {
        for name in filtered {
          match self.env.get(name) {
            Some(value) =>
              self.stdout_buf.write_string("declare -- \{name}=\"\{value}\"\n")
            None => {
              self.stderr_buf.write_string("moon_bash: declare: \{name}: not found\n")
              failed = true
            }
          }
        }
      }
    }
    self.exit_code = if failed { 1 } else { 0 }
    return
  }

  if nameref {
    for spec in filtered {
      match parse_name_value_spec(spec) {
        Some((name, Some(target))) => {
          self.capture_local_binding(name)
          self.env[name] = target
          self.env["__MOON_BASH_NAMEREF__" + name] = target
        }
        Some((name, None)) => {
          self.capture_local_binding(name)
          if not(self.env.contains(name)) {
            self.env[name] = ""
          }
        }
        None => ()
      }
    }
    self.exit_code = 0
    return
  }

  if filtered.length() == 0 {
    self.exit_code = 0
    return
  }

  if not(
    readonly_mode || integer_mode || lowercase_mode || uppercase_mode || export_mode
  ) {
    self.builtin_local(filtered)
    return
  }

  let mut failed = false
  for spec in filtered {
    match parse_name_value_spec(spec) {
      Some((name, assigned_value)) => {
        self.capture_local_binding(name)
        if readonly_mode {
          self.set_readonly_variable(name, true)
        }
        if integer_mode {
          self.set_integer_attribute(name, true)
        }
        if lowercase_mode {
          self.set_lower_attribute(name, true)
        }
        if uppercase_mode {
          self.set_upper_attribute(name, true)
        }
        if lowercase_mode && uppercase_mode {
          self.set_lower_attribute(name, false)
        }
        if export_mode {
          self.exported[name] = true
        }
        match assigned_value {
          Some(value) => {
            if not(self.store_scalar_assignment_with_options(name, value, false)) {
              failed = true
              break
            }
          }
          None => {
            if not(self.env.contains(name)) {
              if not(self.store_scalar_assignment_with_options(name, "", false)) {
                failed = true
                break
              }
            }
          }
        }
      }
      None => ()
    }
  }
  self.exit_code = if failed { 1 } else { 0 }
}

fn declare_flag_contains(flag : String, needle : Char) -> Bool {
  if flag.length() <= 1 {
    return false
  }
  for i = 1; i < flag.length(); i = i + 1 {
    if flag[i].to_int().unsafe_to_char() == needle {
      return true
    }
  }
  false
}

fn ExecContext::builtin_readonly(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  let declare_args : Array[String] = ["-r"]
  for arg in args {
    declare_args.push(arg)
  }
  self.builtin_declare(declare_args)
}

fn ExecContext::builtin_getopts(
  self : ExecContext,
  args : Array[String]
) -> Unit {
  if args.length() < 2 {
    self.exit_code = 1
    return
  }

  let opt_spec = args[0]
  let target_name = args[1]
  let parse_args : Array[String] = []
  if args.length() > 2 {
    for i = 2; i < args.length(); i = i + 1 {
      parse_args.push(args[i])
    }
  } else {
    let argc = parse_int32_str(self.env.get("#").unwrap_or("0"))
    for i = 1; i <= argc; i = i + 1 {
      parse_args.push(self.env.get(i.to_string()).unwrap_or(""))
    }
  }

  let mut optind = parse_int32_str(self.env.get("OPTIND").unwrap_or("1"))
  if optind < 1 {
    optind = 1
  }
  if optind > parse_args.length() {
    self.exit_code = 1
    return
  }

  let current = parse_args[optind - 1]
  if current == "--" {
    self.env["OPTIND"] = (optind + 1).to_string()
    self.exit_code = 1
    return
  }
  if current.length() < 2 || current[0].to_int().unsafe_to_char() != '-' {
    self.exit_code = 1
    return
  }

  let option_char = current[1].to_int().unsafe_to_char()
  if option_char == '-' {
    self.exit_code = 1
    return
  }
  let option_name = getopts_char_string(option_char)
  let opt_idx = getopts_find_option(opt_spec, option_char)
  if opt_idx < 0 {
    if not(self.store_scalar_assignment(target_name, "?")) {
      return
    }
    if not(self.store_scalar_assignment("OPTARG", option_name)) {
      return
    }
    self.env["OPTIND"] = (optind + 1).to_string()
    self.exit_code = 0
    return
  }

  let expects_arg = getopts_option_takes_argument(opt_spec, opt_idx)
  if expects_arg {
    let inline = if current.length() > 2 { current.view(start_offset=2).to_string() } else { "" }
    let optarg = if inline.length() > 0 {
      inline
    } else if optind < parse_args.length() {
      parse_args[optind]
    } else {
      if not(self.store_scalar_assignment(target_name, "?")) {
        return
      }
      self.env["OPTIND"] = (optind + 1).to_string()
      self.exit_code = 0
      return
    }
    if not(self.store_scalar_assignment(target_name, option_name)) {
      return
    }
    if not(self.store_scalar_assignment("OPTARG", optarg)) {
      return
    }
    self.env["OPTIND"] = if inline.length() > 0 {
      (optind + 1).to_string()
    } else {
      (optind + 2).to_string()
    }
    self.exit_code = 0
    return
  }

  if not(self.store_scalar_assignment(target_name, option_name)) {
    return
  }
  self.env.remove("OPTARG")
  self.env["OPTIND"] = (optind + 1).to_string()
  self.exit_code = 0
}

fn parse_name_value_spec(spec : String) -> (String, String?)? {
  if spec.length() == 0 {
    return None
  }
  let mut eq_pos = -1
  for i = 0; i < spec.length(); i = i + 1 {
    if spec[i] == '=' {
      eq_pos = i
      break
    }
  }
  if eq_pos > 0 {
    let name = spec.view(start_offset=0, end_offset=eq_pos).to_string()
    let value = spec.view(start_offset=eq_pos + 1).to_string()
    if name.length() == 0 {
      return None
    }
    return Some((name, Some(value)))
  }
  Some((spec, None))
}

fn getopts_char_string(ch : Char) -> String {
  let buf = StringBuilder::new()
  buf.write_char(ch)
  buf.to_string()
}

fn getopts_find_option(spec : String, ch : Char) -> Int {
  for i = 0; i < spec.length(); i = i + 1 {
    if spec[i].to_int().unsafe_to_char() == ch {
      return i
    }
  }
  -1
}

fn getopts_option_takes_argument(spec : String, opt_idx : Int) -> Bool {
  if opt_idx < 0 || opt_idx + 1 >= spec.length() {
    return false
  }
  spec[opt_idx + 1].to_int().unsafe_to_char() == ':'
}

fn readonly_storage_key(name : String) -> String {
  "__MOON_BASH_READONLY__" + name
}

fn integer_attr_storage_key(name : String) -> String {
  "__MOON_BASH_ATTR_INTEGER__" + name
}

fn lower_attr_storage_key(name : String) -> String {
  "__MOON_BASH_ATTR_LOWER__" + name
}

fn upper_attr_storage_key(name : String) -> String {
  "__MOON_BASH_ATTR_UPPER__" + name
}

fn ExecContext::set_readonly_variable(
  self : ExecContext,
  name : String,
  enabled : Bool
) -> Unit {
  if enabled {
    self.env[readonly_storage_key(name)] = "1"
  } else {
    self.env.remove(readonly_storage_key(name))
  }
}

fn ExecContext::set_integer_attribute(
  self : ExecContext,
  name : String,
  enabled : Bool
) -> Unit {
  if enabled {
    self.env[integer_attr_storage_key(name)] = "1"
  } else {
    self.env.remove(integer_attr_storage_key(name))
  }
}

fn ExecContext::set_lower_attribute(
  self : ExecContext,
  name : String,
  enabled : Bool
) -> Unit {
  if enabled {
    self.env[lower_attr_storage_key(name)] = "1"
  } else {
    self.env.remove(lower_attr_storage_key(name))
  }
}

fn ExecContext::set_upper_attribute(
  self : ExecContext,
  name : String,
  enabled : Bool
) -> Unit {
  if enabled {
    self.env[upper_attr_storage_key(name)] = "1"
  } else {
    self.env.remove(upper_attr_storage_key(name))
  }
}

fn ExecContext::is_readonly_variable(self : ExecContext, name : String) -> Bool {
  self.env.get(readonly_storage_key(name)).unwrap_or("") == "1"
}

fn ExecContext::apply_variable_attributes(
  self : ExecContext,
  name : String,
  value : String
) -> String {
  let mut output = value
  if self.env.get(integer_attr_storage_key(name)).unwrap_or("") == "1" {
    output = self.eval_arith_raw(value).to_string()
  }
  if self.env.get(lower_attr_storage_key(name)).unwrap_or("") == "1" {
    output = to_lower(output)
  }
  if self.env.get(upper_attr_storage_key(name)).unwrap_or("") == "1" {
    output = to_upper(output)
  }
  output
}
