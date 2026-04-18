// moon_bash Interpreter - Common Helpers
// Shared utilities used across interpreter modules.

fn is_shell_builtin(name : String) -> Bool {
  match name {
    "export" | "unset" | "set" | "shift" | "exit" | "return" | "break"
    | "continue" | "read" | "test" | "[" | "[[" | "printf" | "eval" | "source"
    | "." | "local" | "readonly" | "declare" | "typeset" | "getopts" | "let"
    | ":" | "type" | "command" | "builtin" | "hash" | "shopt" | "complete"
    | "compgen" | "compopt" | "pushd" | "popd" | "dirs" | "basename"
    | "dirname" | "seq" | "rev" | "nl" | "fold" | "expand" | "unexpand" | "paste"
    | "column" | "join" | "tr" | "sort" | "uniq" | "cut" | "tee" | "sed" | "grep"
    | "egrep" | "fgrep" | "rg" | "xargs" | "date" | "env" | "printenv"
    | "which" | "whoami" | "hostname" | "help" | "clear" | "history" | "tac"
    | "od" | "alias" | "unalias" | "bash" | "sh" | "time" | "sleep"
    | "timeout" | "mapfile" | "readarray" | "cd" | "pwd" | "echo" | "true"
    | "false" => true
    _ => false
  }
}

fn parse_int_str(s : String) -> Int64 {
  let mut result = 0L
  let mut neg = false
  let mut start = 0
  if s.length() > 0 && s[0] == '-' {
    neg = true
    start = 1
  } else if s.length() > 0 && s[0] == '+' {
    start = 1
  }
  for i = start; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= '0' && ch <= '9' {
      result = result * 10L + (ch.to_int() - '0'.to_int()).to_int64()
    } else {
      break
    }
  }
  if neg { -result } else { result }
}

fn parse_int32_str(s : String) -> Int {
  parse_int_str(s).to_int()
}

fn split_by_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == ' ' || ch == '\t' || ch == '\n' {
      let word = buf.to_string()
      if word.length() > 0 {
        result.push(word)
        buf.reset()
      }
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  result
}

fn split_lines_no_trailing(s : String) -> Array[String] {
  if s.length() == 0 {
    return []
  }
  let lines = split_lines(s)
  // Remove trailing empty line if the input ended with \n
  if lines.length() > 0 && lines[lines.length() - 1] == "" {
    let result : Array[String] = []
    for i = 0; i < lines.length() - 1; i = i + 1 {
      result.push(lines[i])
    }
    result
  } else {
    lines
  }
}

fn repeat_char(ch : Char, count : Int) -> String {
  let out = StringBuilder::new()
  let total = if count < 0 { 0 } else { count }
  for i = 0; i < total; i = i + 1 {
    out.write_char(ch)
  }
  out.to_string()
}

fn contains_substring(haystack : String, needle : String) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  for i = 0; i <= haystack.length() - needle.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < needle.length(); j = j + 1 {
      if haystack[i + j] != needle[j] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }
  false
}


fn substring_slice(s : String, start : Int, end : Int) -> String {
  if start >= end || start < 0 || end > s.length() {
    return ""
  }
  s.view(start_offset=start, end_offset=end).to_string()
}


fn parse_field_spec(spec : String) -> Array[Int] {
  let fields : Array[Int] = []
  let parts = split_string_by_delimiter(spec, ",")
  for part in parts {
    // Handle ranges like 1-3
    if contains_substring(part, "-") {
      let range_parts = split_string_by_delimiter(part, "-")
      if range_parts.length() == 2 {
        let start = parse_int32_str(range_parts[0])
        let end = parse_int32_str(range_parts[1])
        for i = start; i <= end; i = i + 1 {
          fields.push(i)
        }
      }
    } else {
      fields.push(parse_int32_str(part))
    }
  }
  fields
}

fn split_string_by_delimiter(s : String, delim : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let delim_len = delim.length()
  if delim_len == 0 {
    result.push(s)
    return result
  }
  let mut i = 0
  while i < s.length() {
    let mut match_found = true
    if i + delim_len <= s.length() {
      for j = 0; j < delim_len; j = j + 1 {
        if s[i + j] != delim[j] {
          match_found = false
          break
        }
      }
    } else {
      match_found = false
    }
    if match_found {
      result.push(buf.to_string())
      buf.reset()
      i += delim_len
    } else {
      buf.write_char(s[i].to_int().unsafe_to_char())
      i += 1
    }
  }
  result.push(buf.to_string())
  result
}

fn find_substring_offset(text : String, fragment : String) -> Int {
  if fragment.length() == 0 {
    return 0
  }
  if fragment.length() > text.length() {
    return -1
  }
  for i = 0; i <= text.length() - fragment.length(); i = i + 1 {
    let mut matched = true
    for j = 0; j < fragment.length(); j = j + 1 {
      if text[i + j] != fragment[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

fn ExecContext::line_number_for_fragment(self : ExecContext, fragment : String) -> Int {
  let script = self.current_script
  if script.length() == 0 {
    return 1
  }
  let offset = find_substring_offset(script, fragment)
  if offset < 0 {
    return 1
  }
  let mut line = 1
  for i = 0; i < offset; i = i + 1 {
    if script[i].to_int().unsafe_to_char() == '\n' {
      line += 1
    }
  }
  let adjusted = line - 4
  if adjusted > 0 { adjusted } else { 1 }
}

fn ExecContext::emit_bad_array_subscript(
  self : ExecContext,
  subject : String,
  fragment : String
) -> Unit {
  let line = self.line_number_for_fragment(fragment)
  self.stderr_buf.write_string(
    "bash: line \{line.to_string()}: \{subject}: bad array subscript\n",
  )
}

priv enum TestEvalMode {
  TestBuiltin
  BracketBuiltin
  DoubleBracketBuiltin
}

priv struct TestEvalResult {
  value : Bool
  status : Int
}

priv struct TestExprParser {
  tokens : Array[String]
  mut pos : Int
}

fn test_eval_ok(value : Bool) -> TestEvalResult {
  { value, status: 0 }
}

fn test_eval_syntax_error() -> TestEvalResult {
  { value: false, status: 2 }
}

let test_token_tilde_prefix : UInt16 = '\u0006'
let test_token_dynamic_prefix : UInt16 = '\u0007'

fn test_encode_tilde_token(raw : String) -> String {
  "\u0006" + raw
}

fn test_encode_dynamic_token(raw : String) -> String {
  "\u0007" + raw
}

fn test_token_has_meta(token : String) -> Bool {
  token.length() > 0 &&
  (token[0] == test_token_tilde_prefix || token[0] == test_token_dynamic_prefix)
}

fn test_token_is_tilde(token : String) -> Bool {
  token.length() > 0 && token[0] == test_token_tilde_prefix
}

fn test_token_raw(token : String) -> String {
  if test_token_has_meta(token) {
    token.view(start_offset=1).to_string()
  } else {
    token
  }
}

fn test_token_can_be_operator(token : String) -> Bool {
  !(test_token_has_meta(token))
}

fn TestExprParser::peek(self : TestExprParser) -> String? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

fn test_slice_args(args : Array[String], start : Int, end_ : Int) -> Array[String] {
  let out : Array[String] = []
  for i = start; i < end_; i = i + 1 {
    out.push(args[i])
  }
  out
}

fn test_is_logical_or_op(op : String) -> Bool {
  op == "-o" || op == "||"
}

fn test_is_logical_and_op(op : String) -> Bool {
  op == "-a" || op == "&&"
}

fn test_is_unary_op(op : String) -> Bool {
  match op {
    "-a" | "-e" | "-f" | "-d" | "-s" | "-r" | "-w" | "-x" | "-L" | "-h"
    | "-k" | "-O" | "-G" | "-u" | "-g" | "-b" | "-c" | "-S" | "-p"
    | "-t" | "-v" | "-o" | "-z" | "-n" => true
    _ => false
  }
}

fn test_is_binary_op(op : String) -> Bool {
  match op {
    "=" | "==" | "!=" | "<" | ">" | "=~" | "-eq" | "-ne" | "-lt" | "-le"
    | "-gt" | "-ge" | "-nt" | "-ot" | "-ef" => true
    _ => false
  }
}

fn test_mode_is_double_bracket(mode : TestEvalMode) -> Bool {
  match mode {
    TestEvalMode::DoubleBracketBuiltin => true
    _ => false
  }
}

fn test_parse_decimal_operand(text : String) -> Int64? {
  let trimmed = arith_trim(text)
  if trimmed.length() == 0 {
    return None
  }
  let mut start = 0
  let mut sign = 1L
  if trimmed[0] == '+' {
    start = 1
  } else if trimmed[0] == '-' {
    start = 1
    sign = -1L
  }
  if start >= trimmed.length() {
    return None
  }
  let mut value = 0L
  for i = start; i < trimmed.length(); i = i + 1 {
    let ch = trimmed[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10L + (ch.to_int() - '0'.to_int()).to_int64()
  }
  Some(value * sign)
}

fn test_parse_fd_operand(text : String) -> Int64? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0L
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10L + (ch.to_int() - '0'.to_int()).to_int64()
    if value > 2_147_483_647L {
      return None
    }
  }
  Some(value)
}

fn test_entry_mode(entry : @fs.FsEntry) -> Int {
  match entry {
    @fs.FsEntry::File(data) => data.mode
    @fs.FsEntry::Directory(data) => data.mode
    @fs.FsEntry::Symlink(data) => data.mode
  }
}

fn test_entry_mtime(entry : @fs.FsEntry) -> Int64 {
  match entry {
    @fs.FsEntry::File(data) => data.mtime
    @fs.FsEntry::Directory(data) => data.mtime
    @fs.FsEntry::Symlink(data) => data.mtime
  }
}

fn ExecContext::test_lookup_entry(
  self : ExecContext,
  arg : String,
  follow_symlink : Bool
) -> @fs.FsEntry? {
  let resolved = try {
    @fs.resolve_path(self.cwd, arg)
  } catch {
    _ => return None
  }
  if !(follow_symlink) {
    return self.fs.entries.get(resolved)
  }
  let mut current = resolved
  for i = 0; i < 40; i = i + 1 {
    match self.fs.entries.get(current) {
      Some(@fs.FsEntry::Symlink(data)) => {
        current = try {
          if data.target.length() > 0 && data.target[0] == '/' {
            @fs.resolve_path("/", data.target)
          } else {
            @fs.resolve_path(@fs.parent_path(current), data.target)
          }
        } catch {
          _ => return None
        }
      }
      Some(entry) => return Some(entry)
      None => return None
    }
  }
  None
}

fn test_shell_option_enabled(ctx : ExecContext, name : String) -> Bool? {
  match name {
    "pipefail" => Some(ctx.options.pipefail)
    "errexit" => Some(ctx.options.errexit)
    "nounset" => Some(ctx.options.nounset)
    "noglob" => Some(ctx.options.noglob)
    "xtrace" => Some(ctx.options.xtrace)
    "noclobber" => Some(ctx.options.noclobber)
    "allexport" => Some(ctx.options.allexport)
    _ => None
  }
}

fn ExecContext::test_eval_unary_with_status(
  self : ExecContext,
  op : String,
  arg : String
) -> TestEvalResult {
  let op_text = test_token_raw(op)
  let arg_text = test_token_raw(arg)
  match op_text {
    "-z" => test_eval_ok(arg_text.length() == 0)
    "-n" => test_eval_ok(arg_text.length() > 0)
    "-a" | "-e" => test_eval_ok(self.test_lookup_entry(arg_text, true) is Some(_))
    "-f" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(@fs.FsEntry::File(_)) => true
          _ => false
        },
      )
    "-d" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(@fs.FsEntry::Directory(_)) => true
          _ => false
        },
      )
    "-s" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(@fs.FsEntry::File(data)) => data.content.length() > 0
          _ => false
        },
      )
    "-r" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(entry) => test_entry_mode(entry).land(0o444) != 0
          None => false
        },
      )
    "-w" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(entry) => test_entry_mode(entry).land(0o222) != 0
          None => false
        },
      )
    "-x" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(entry) => test_entry_mode(entry).land(0o111) != 0
          None => false
        },
      )
    "-L" | "-h" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, false) {
          Some(@fs.FsEntry::Symlink(_)) => true
          _ => false
        },
      )
    "-k" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(entry) => test_entry_mode(entry).land(0o1000) != 0
          None => false
        },
      )
    "-O" | "-G" => test_eval_ok(self.test_lookup_entry(arg_text, true) is Some(_))
    "-u" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(entry) => test_entry_mode(entry).land(0o4000) != 0
          None => false
        },
      )
    "-g" =>
      test_eval_ok(
        match self.test_lookup_entry(arg_text, true) {
          Some(entry) => test_entry_mode(entry).land(0o2000) != 0
          None => false
        },
      )
    "-b" | "-S" | "-p" => test_eval_ok(false)
    "-c" => test_eval_ok(arg_text == "/dev/zero")
    "-t" =>
      match test_parse_fd_operand(arg_text) {
        Some(_fd) => test_eval_ok(false)
        None => test_eval_syntax_error()
      }
    "-v" => test_eval_ok(test_var_is_set(arg_text, self))
    "-o" =>
      match test_shell_option_enabled(self, arg_text) {
        Some(enabled) => test_eval_ok(enabled)
        None => test_eval_ok(false)
      }
    _ => test_eval_syntax_error()
  }
}

fn ExecContext::test_eval_binary_with_status(
  self : ExecContext,
  left : String,
  op : String,
  right : String,
  mode : TestEvalMode
) -> TestEvalResult {
  let left_text = test_token_raw(left)
  let op_text = test_token_raw(op)
  let right_text = test_token_raw(right)
  let left_value = test_unescape_glob_escapes(left_text)
  let right_value = test_unescape_glob_escapes(right_text)
  let literal_compare = match mode {
    TestEvalMode::TestBuiltin => true
    TestEvalMode::BracketBuiltin => true
    TestEvalMode::DoubleBracketBuiltin => false
  }
  match op_text {
    "=" | "==" =>
      test_eval_ok(
        if literal_compare {
          left_text == right_text
        } else {
          test_string_compare(left_value, right_text)
        },
      )
    "!=" =>
      test_eval_ok(
        if literal_compare {
          left_text != right_text
        } else {
          !(test_string_compare(left_value, right_text))
        },
      )
    "<" => test_eval_ok(left_value < right_value)
    ">" => test_eval_ok(left_value > right_value)
    "=~" => {
      let pattern = if test_token_is_tilde(right) {
        test_escape_regex_literal(right_value)
      } else {
        right_value
      }
      self.test_eval_regex_with_status(left_value, pattern)
    }
    "-eq" | "-ne" | "-lt" | "-le" | "-gt" | "-ge" => {
      let left_value = if test_mode_is_double_bracket(mode) {
        self.test_parse_double_bracket_numeric_operand(left_text)
      } else {
        test_parse_decimal_operand(left_text)
      }
      match left_value {
        Some(l) => {
          let right_value = if test_mode_is_double_bracket(mode) {
            self.test_parse_double_bracket_numeric_operand(right_text)
          } else {
            test_parse_decimal_operand(right_text)
          }
          match right_value {
            Some(r) =>
              test_eval_ok(
                match op_text {
                  "-eq" => l == r
                  "-ne" => l != r
                  "-lt" => l < r
                  "-le" => l <= r
                  "-gt" => l > r
                  "-ge" => l >= r
                  _ => false
                },
              )
            None => if test_mode_is_double_bracket(mode) { test_eval_ok(false) } else { test_eval_syntax_error() }
          }
        }
        None => if test_mode_is_double_bracket(mode) { test_eval_ok(false) } else { test_eval_syntax_error() }
      }
    }
    "-nt" =>
      match self.test_lookup_entry(left_text, true) {
        Some(left_entry) =>
          match self.test_lookup_entry(right_text, true) {
            Some(right_entry) => test_eval_ok(test_entry_mtime(left_entry) > test_entry_mtime(right_entry))
            None => test_eval_ok(false)
          }
        None => test_eval_ok(false)
      }
    "-ot" =>
      match self.test_lookup_entry(left_text, true) {
        Some(left_entry) =>
          match self.test_lookup_entry(right_text, true) {
            Some(right_entry) => test_eval_ok(test_entry_mtime(left_entry) < test_entry_mtime(right_entry))
            None => test_eval_ok(false)
          }
        None => test_eval_ok(false)
      }
    "-ef" => test_eval_ok(false)
    _ => test_eval_syntax_error()
  }
}

fn ExecContext::test_parse_double_bracket_numeric_operand(
  self : ExecContext,
  text : String
) -> Int64? {
  let trimmed = arith_trim(text)
  if trimmed.length() == 0 {
    return Some(0L)
  }
  let saved_exit_code = self.exit_code
  let saved_should_exit = self.should_exit
  self.env.remove("__MOON_BASH_ABORT_CURRENT_COMMAND__")
  let value = self.eval_arith(@ast.ArithExpr::Raw(trimmed))
  if self.env.contains("__MOON_BASH_ABORT_CURRENT_COMMAND__") {
    self.env.remove("__MOON_BASH_ABORT_CURRENT_COMMAND__")
    self.exit_code = saved_exit_code
    self.should_exit = saved_should_exit
    return Some(0L)
  }
  self.exit_code = saved_exit_code
  self.should_exit = saved_should_exit
  Some(value)
}

fn ExecContext::test_eval_regex_with_status(
  self : ExecContext,
  text : String,
  pattern : String
) -> TestEvalResult {
  let matcher = try {
    @regex.compile_grep_matcher(
      pattern,
      extended=true,
      fixed=false,
      ignore_case=false,
    )
  } catch {
    _ => {
      self.store_array_assignment("BASH_REMATCH", [])
      return test_eval_syntax_error()
    }
  }
  match matcher.find_first_with_groups(text) {
    Some((start, end, groups)) => {
      let values : Array[String] = []
      values.push(text.view(start_offset=start, end_offset=end).to_string())
      for group in groups {
        values.push(group)
      }
      self.store_array_assignment("BASH_REMATCH", values)
      test_eval_ok(true)
    }
    None => {
      self.store_array_assignment("BASH_REMATCH", [])
      test_eval_ok(false)
    }
  }
}

fn test_eval_string_operand(arg : String) -> Bool {
  test_token_raw(arg).length() > 0
}

fn test_eval_negated(result : TestEvalResult) -> TestEvalResult {
  if result.status != 0 {
    result
  } else {
    test_eval_ok(!(result.value))
  }
}

fn ExecContext::test_eval_small_arity(
  self : ExecContext,
  args : Array[String],
  mode : TestEvalMode
) -> TestEvalResult {
  match args.length() {
    0 =>
      match mode {
        TestEvalMode::DoubleBracketBuiltin => test_eval_syntax_error()
        _ => test_eval_ok(false)
      }
    1 => {
      if test_mode_is_double_bracket(mode) {
        let token = args[0]
        let token_text = test_token_raw(token)
        if test_token_can_be_operator(token) &&
          (token_text == "!" ||
          token_text == "(" ||
          token_text == ")" ||
          test_is_unary_op(token_text) ||
          test_is_binary_op(token_text) ||
          test_is_logical_and_op(token_text) ||
          test_is_logical_or_op(token_text)) {
          return test_eval_syntax_error()
        }
      }
      test_eval_ok(test_eval_string_operand(args[0]))
    }
    2 => {
      let op = args[0]
      let arg = args[1]
      let op_text = test_token_raw(op)
      let arg_text = test_token_raw(arg)
      if test_token_can_be_operator(op) && op_text == "!" {
        test_eval_ok(!(test_eval_string_operand(args[1])))
      } else if test_token_can_be_operator(op) && test_is_unary_op(op_text) {
        if test_mode_is_double_bracket(mode) &&
          test_token_can_be_operator(arg) &&
          (arg_text == "!" ||
          arg_text == "(" ||
          arg_text == ")" ||
          test_is_logical_and_op(arg_text) ||
          test_is_logical_or_op(arg_text) ||
          test_is_binary_op(arg_text)) {
          test_eval_syntax_error()
        } else {
          self.test_eval_unary_with_status(op, arg)
        }
      } else {
        test_eval_syntax_error()
      }
    }
    3 => {
      let left = args[0]
      let op = args[1]
      let right = args[2]
      let left_text = test_token_raw(left)
      let op_text = test_token_raw(op)
      let right_text = test_token_raw(right)
      if test_token_can_be_operator(op) && test_is_binary_op(op_text) {
        self.test_eval_binary_with_status(left, op, right, mode)
      } else if test_token_can_be_operator(left) && left_text == "!" {
        test_eval_negated(self.test_eval_small_arity(test_slice_args(args, 1, 3), mode))
      } else if test_token_can_be_operator(left) &&
        test_token_can_be_operator(right) &&
        left_text == "(" &&
        right_text == ")" {
        test_eval_ok(test_eval_string_operand(op))
      } else if test_token_can_be_operator(op) &&
        test_is_logical_and_op(op_text) &&
        !(test_mode_is_double_bracket(mode)) {
        test_eval_ok(test_eval_string_operand(left) && test_eval_string_operand(right))
      } else if test_token_can_be_operator(op) &&
        test_is_logical_or_op(op_text) &&
        !(test_mode_is_double_bracket(mode)) {
        test_eval_ok(test_eval_string_operand(left) || test_eval_string_operand(right))
      } else {
        test_eval_syntax_error()
      }
    }
    4 => {
      if test_token_can_be_operator(args[0]) && test_token_raw(args[0]) == "!" {
        test_eval_negated(self.test_eval_small_arity(test_slice_args(args, 1, 4), mode))
      } else if test_token_can_be_operator(args[0]) &&
        test_token_can_be_operator(args[3]) &&
        test_token_raw(args[0]) == "(" &&
        test_token_raw(args[3]) == ")" {
        self.test_eval_small_arity(test_slice_args(args, 1, 3), mode)
      } else {
        test_eval_syntax_error()
      }
    }
    _ => test_eval_syntax_error()
  }
}

fn ExecContext::test_parse_or_expr(
  self : ExecContext,
  parser : TestExprParser,
  mode : TestEvalMode
) -> TestEvalResult {
  let mut left = self.test_parse_and_expr(parser, mode)
  if left.status != 0 {
    return left
  }
  while parser.pos < parser.tokens.length() &&
    test_token_can_be_operator(parser.tokens[parser.pos]) &&
    test_is_logical_or_op(test_token_raw(parser.tokens[parser.pos])) {
    parser.pos += 1
    let right = self.test_parse_and_expr(parser, mode)
    if right.status != 0 {
      return right
    }
    left = test_eval_ok(left.value || right.value)
  }
  left
}

fn ExecContext::test_parse_and_expr(
  self : ExecContext,
  parser : TestExprParser,
  mode : TestEvalMode
) -> TestEvalResult {
  let mut left = self.test_parse_not_expr(parser, mode)
  if left.status != 0 {
    return left
  }
  while parser.pos < parser.tokens.length() &&
    test_token_can_be_operator(parser.tokens[parser.pos]) &&
    test_is_logical_and_op(test_token_raw(parser.tokens[parser.pos])) {
    parser.pos += 1
    let right = self.test_parse_not_expr(parser, mode)
    if right.status != 0 {
      return right
    }
    left = test_eval_ok(left.value && right.value)
  }
  left
}

fn ExecContext::test_parse_not_expr(
  self : ExecContext,
  parser : TestExprParser,
  mode : TestEvalMode
) -> TestEvalResult {
  match parser.peek() {
    Some(tok) => {
      if test_token_can_be_operator(tok) && test_token_raw(tok) == "!" {
        parser.pos += 1
        let inner = self.test_parse_not_expr(parser, mode)
        if inner.status != 0 {
          return inner
        }
        return test_eval_ok(!(inner.value))
      }
    }
    None => return test_eval_syntax_error()
  }
  self.test_parse_primary_expr(parser, mode)
}

fn ExecContext::test_parse_primary_expr(
  self : ExecContext,
  parser : TestExprParser,
  mode : TestEvalMode
) -> TestEvalResult {
  match parser.peek() {
    None => test_eval_syntax_error()
    Some(tok) => {
      let tok_text = test_token_raw(tok)
      let tok_is_operator = test_token_can_be_operator(tok)
      if tok_is_operator && tok_text == "(" {
        parser.pos += 1
        let inner = self.test_parse_or_expr(parser, mode)
        if inner.status != 0 {
          return inner
        }
        if parser.pos >= parser.tokens.length() ||
          !(test_token_can_be_operator(parser.tokens[parser.pos])) ||
          test_token_raw(parser.tokens[parser.pos]) != ")" {
          return test_eval_syntax_error()
        }
        parser.pos += 1
        return inner
      }
      if tok_is_operator &&
        (tok_text == ")" ||
        test_is_logical_and_op(tok_text) ||
        test_is_logical_or_op(tok_text) ||
        test_is_binary_op(tok_text)) {
        return test_eval_syntax_error()
      }
      if tok_is_operator && test_is_unary_op(tok_text) {
        if parser.pos + 1 >= parser.tokens.length() {
          return test_eval_syntax_error()
        }
        let arg = parser.tokens[parser.pos + 1]
        parser.pos += 2
        return self.test_eval_unary_with_status(tok, arg)
      }
      if parser.pos + 2 < parser.tokens.length() {
        let op = parser.tokens[parser.pos + 1]
        if test_token_can_be_operator(op) && test_is_binary_op(test_token_raw(op)) {
          let left = parser.tokens[parser.pos]
          let right = parser.tokens[parser.pos + 2]
          parser.pos += 3
          return self.test_eval_binary_with_status(left, op, right, mode)
        }
      }
      parser.pos += 1
      test_eval_ok(test_eval_string_operand(tok))
    }
  }
}

fn ExecContext::evaluate_test_with_status(
  self : ExecContext,
  args : Array[String],
  mode : TestEvalMode
) -> TestEvalResult {
  if args.length() <= 4 {
    return self.test_eval_small_arity(args, mode)
  }
  let parser : TestExprParser = { tokens: args, pos: 0 }
  let result = self.test_parse_or_expr(parser, mode)
  if result.status != 0 {
    return result
  }
  if parser.pos != parser.tokens.length() {
    return test_eval_syntax_error()
  }
  result
}

fn test_var_is_set(name : String, ctx : ExecContext) -> Bool {
  match parse_array_reference_name(name) {
    Some((base, index)) => {
      if index == "@" || index == "*" {
        let count = parse_int32_str(ctx.env.get(test_array_count_storage_key(base)).unwrap_or("-1"))
        if count >= 0 {
          return count > 0
        }
        return ctx.env.contains(base) || ctx.env.contains(base + "[@]")
      }
      let kind = ctx.env.get(test_array_kind_storage_key(base)).unwrap_or("")
      if kind == "assoc" {
        let resolved_index = ctx.expand_array_index_expr(index)
        if resolved_index.length() > 0 && ctx.env.contains("\{base}[\{resolved_index}]") {
          return true
        }
        return ctx.env.contains("\{base}[\{index}]")
      }
      let key = test_indexed_lookup_key(base, index, ctx)
      ctx.env.contains(key)
    }
    None => {
      match ctx.env.get(test_array_count_storage_key(name)) {
        Some(count_text) => parse_int32_str(count_text) > 0
        None => ctx.env.contains(name)
      }
    }
  }
}

fn test_array_count_storage_key(name : String) -> String {
  "__MOON_BASH_ARRAY_COUNT__" + name
}

fn test_array_kind_storage_key(name : String) -> String {
  "__MOON_BASH_ARRAY_KIND__" + name
}

fn test_indexed_lookup_key(
  base : String,
  index_expr : String,
  ctx : ExecContext
) -> String {
  let trimmed = trim_ascii_space_simple(index_expr)
  if trimmed.length() == 0 {
    return "\{base}[\{index_expr}]"
  }

  let raw_index = if arith_is_identifier_text(trimmed) {
    let referenced = trim_ascii_space_simple(ctx.env.get(trimmed).unwrap_or(""))
    if referenced.length() > 0 && contains_test_arith_operator(referenced) {
      ctx.eval_arith(@ast.ArithExpr::Raw(referenced))
    } else {
      ctx.eval_arith(@ast.ArithExpr::Raw(trimmed))
    }
  } else {
    ctx.eval_arith(@ast.ArithExpr::Raw(trimmed))
  }
  let resolved = if raw_index < 0L {
    ctx.indexed_array_origin(base) + raw_index
  } else {
    raw_index
  }
  if resolved < 0L {
    let fragment = "\{base}[\{trimmed}]"
    ctx.emit_bad_array_subscript(base, fragment)
    ctx.exit_code = 1
    ctx.should_exit = true
    return "\{base}[\{index_expr}]"
  }
  "\{base}[\{resolved.to_string()}]"
}

fn contains_test_arith_operator(text : String) -> Bool {
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i].to_int().unsafe_to_char()
    if ch == '+' ||
      ch == '-' ||
      ch == '*' ||
      ch == '/' ||
      ch == '%' ||
      ch == '&' ||
      ch == '|' ||
      ch == '^' ||
      ch == '<' ||
      ch == '>' ||
      ch == '(' ||
      ch == ')' ||
      ch == '?' ||
      ch == ':' ||
      ch == '[' ||
      ch == ']' {
      return true
    }
  }
  false
}

fn test_string_compare(left : String, right : String) -> Bool {
  if has_glob_meta(right) || test_has_glob_escape(right) {
    simple_pattern_match(left, right)
  } else {
    left == right
  }
}

fn test_has_glob_escape(s : String) -> Bool {
  let mut i = 0
  while i + 1 < s.length() {
    if s[i].to_int().unsafe_to_char() == '\\' {
      let next = s[i + 1].to_int().unsafe_to_char()
      if next == '*' || next == '?' || next == '[' || next == '\\' {
        return true
      }
      i += 2
      continue
    }
    i += 1
  }
  false
}

fn test_unescape_glob_escapes(s : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < s.length() {
      let next = s[i + 1].to_int().unsafe_to_char()
      if next == '*' || next == '?' || next == '[' || next == '\\' {
        out.write_char(next)
        i += 2
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn test_escape_regex_literal(s : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' ||
      ch == '.' ||
      ch == '^' ||
      ch == '$' ||
      ch == '*' ||
      ch == '+' ||
      ch == '?' ||
      ch == '(' ||
      ch == ')' ||
      ch == '[' ||
      ch == ']' ||
      ch == '{' ||
      ch == '}' ||
      ch == '|' {
      out.write_char('\\')
    }
    out.write_char(ch)
  }
  out.to_string()
}

// ============================================================================
// Printf Implementation
// ============================================================================

fn format_printf(format : String, args : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut arg_idx = 0
  let mut first_pass = true
  while true {
    let start_arg_idx = arg_idx
    let mut i = 0
    while i < format.length() {
      let ch = format[i].to_int().unsafe_to_char()
      if ch == '\\' && i + 1 < format.length() {
        let next = format[i + 1].to_int().unsafe_to_char()
        if next == 'x' {
          let mut j = i + 2
          let mut value = 0
          let mut digits = 0
          while j < format.length() && digits < 2 {
            let hex_ch = format[j].to_int().unsafe_to_char()
            match printf_hex_digit_value(hex_ch) {
              Some(hex_value) => {
                value = value * 16 + hex_value
                digits += 1
                j += 1
              }
              None => break
            }
          }
          if digits > 0 {
            buf.write_char(value.unsafe_to_char())
            i = j
          } else {
            buf.write_char('x')
            i += 2
          }
          continue
        }
        if printf_is_octal_digit(next) {
          let mut j = i + 1
          let mut value = 0
          let mut digits = 0
          while j < format.length() && digits < 3 {
            let oct_ch = format[j].to_int().unsafe_to_char()
            if !(printf_is_octal_digit(oct_ch)) {
              break
            }
            value = value * 8 + (oct_ch.to_int() - '0'.to_int())
            digits += 1
            j += 1
          }
          buf.write_char(value.unsafe_to_char())
          i = j
          continue
        }
        match next {
          'n' => { buf.write_char('\n'); i += 2 }
          't' => { buf.write_char('\t'); i += 2 }
          '\\' => { buf.write_char('\\'); i += 2 }
          '"' => { buf.write_char('"'); i += 2 }
          _ => { buf.write_char('\\'); buf.write_char(next); i += 2 }
        }
      } else if ch == '%' {
        if i + 1 >= format.length() {
          buf.write_char('%')
          i += 1
          continue
        }

        let mut j = i + 1
        let mut left_justify = false
        let mut zero_pad = false
        while j < format.length() {
          let flag = format[j].to_int().unsafe_to_char()
          if flag == '-' {
            left_justify = true
            j += 1
            continue
          }
          if flag == '0' {
            zero_pad = true
            j += 1
            continue
          }
          break
        }

        let mut width = 0
        while j < format.length() {
          let digit = format[j].to_int().unsafe_to_char()
          if !(printf_is_digit(digit)) {
            break
          }
          width = width * 10 + (digit.to_int() - '0'.to_int())
          j += 1
        }

        let mut precision : Int? = None
        if j < format.length() && format[j].to_int().unsafe_to_char() == '.' {
          j += 1
          let mut p = 0
          let mut has_digits = false
          while j < format.length() {
            let digit = format[j].to_int().unsafe_to_char()
            if !(printf_is_digit(digit)) {
              break
            }
            has_digits = true
            p = p * 10 + (digit.to_int() - '0'.to_int())
            j += 1
          }
          if has_digits {
            precision = Some(p)
          } else {
            precision = Some(0)
          }
        }

        if j >= format.length() {
          buf.write_char('%')
          i += 1
          continue
        }

        let spec = format[j].to_int().unsafe_to_char()
        if spec == '%' {
          let rendered = printf_apply_width(
            "%",
            width,
            left_justify,
            false,
          )
          buf.write_string(rendered)
          i = j + 1
          continue
        }

        let arg = if arg_idx < args.length() { args[arg_idx] } else { "" }
        if arg_idx < args.length() {
          arg_idx += 1
        }

        let mut rendered = match spec {
          's' => {
            match precision {
              Some(p) => {
                if p < arg.length() {
                  substring_slice(arg, 0, p)
                } else {
                  arg
                }
              }
              None => arg
            }
          }
          'd' => {
            let value = parse_int_str(arg)
            printf_format_decimal(value, precision)
          }
          'x' => {
            let value = parse_int_str(arg)
            printf_to_hex(value)
          }
          'f' => {
            let p = precision.unwrap_or(6)
            printf_format_float(arg, p)
          }
          'q' => printf_shell_quote(arg)
          _ => {
            buf.write_char('%')
            i += 1
            continue
          }
        }

        let allow_zero_pad = zero_pad &&
          !(left_justify) &&
          (precision is None) &&
          (spec == 'd' || spec == 'x' || spec == 'f')
        rendered = printf_apply_width(
          rendered,
          width,
          left_justify,
          allow_zero_pad,
        )
        buf.write_string(rendered)
        i = j + 1
      } else {
        buf.write_char(ch)
        i += 1
      }
    }

    if first_pass {
      first_pass = false
    }
    if args.length() == 0 || arg_idx >= args.length() || arg_idx == start_arg_idx {
      break
    }
  }
  buf.to_string()
}

fn printf_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn printf_is_octal_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '7'
}

fn printf_hex_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    return Some(ch.to_int() - '0'.to_int())
  }
  if ch >= 'a' && ch <= 'f' {
    return Some(10 + (ch.to_int() - 'a'.to_int()))
  }
  if ch >= 'A' && ch <= 'F' {
    return Some(10 + (ch.to_int() - 'A'.to_int()))
  }
  None
}

fn printf_repeat_char(ch : Char, count : Int) -> String {
  if count <= 0 {
    return ""
  }
  let out = StringBuilder::new()
  for i = 0; i < count; i = i + 1 {
    out.write_char(ch)
  }
  out.to_string()
}

fn printf_apply_width(
  value : String,
  width : Int,
  left_justify : Bool,
  zero_pad : Bool
) -> String {
  if width <= value.length() {
    return value
  }
  let pad_len = width - value.length()
  if left_justify {
    return value + printf_repeat_char(' ', pad_len)
  }
  if zero_pad &&
    value.length() > 0 &&
    value[0].to_int().unsafe_to_char() == '-' {
    return "-" + printf_repeat_char('0', pad_len) + substring_slice(value, 1, value.length())
  }
  let pad_ch = if zero_pad { '0' } else { ' ' }
  printf_repeat_char(pad_ch, pad_len) + value
}

fn printf_to_hex(value : Int64) -> String {
  if value == 0L {
    return "0"
  }
  let mut v = if value < 0L { -value } else { value }
  let out = StringBuilder::new()
  while v > 0L {
    let digit = v % 16L
    let ch = if digit < 10L {
      (digit + '0'.to_int().to_int64()).to_int().unsafe_to_char()
    } else {
      (digit - 10L + 'a'.to_int().to_int64()).to_int().unsafe_to_char()
    }
    out.write_char(ch)
    v = v / 16L
  }
  let rev = reverse_string(out.to_string())
  if value < 0L {
    "-" + rev
  } else {
    rev
  }
}

fn printf_format_decimal(value : Int64, precision : Int?) -> String {
  let text = value.to_string()
  match precision {
    None => text
    Some(p) => {
      if p <= 0 {
        return text
      }
      let negative = text.length() > 0 && text[0].to_int().unsafe_to_char() == '-'
      let digits = if negative { substring_slice(text, 1, text.length()) } else { text }
      if digits.length() >= p {
        text
      } else {
        let padded = printf_repeat_char('0', p - digits.length()) + digits
        if negative {
          "-" + padded
        } else {
          padded
        }
      }
    }
  }
}

fn printf_shell_quote(value : String) -> String {
  if value.length() == 0 {
    return "''"
  }

  let mut safe = true
  for i = 0; i < value.length(); i = i + 1 {
    let ch = value[i].to_int().unsafe_to_char()
    if !(printf_is_shell_safe_char(ch)) {
      safe = false
      break
    }
  }
  if safe {
    return value
  }

  let out = StringBuilder::new()
  out.write_char('\'')
  for i = 0; i < value.length(); i = i + 1 {
    let ch = value[i].to_int().unsafe_to_char()
    if ch == '\'' {
      out.write_string("'\\''")
    } else {
      out.write_char(ch)
    }
  }
  out.write_char('\'')
  out.to_string()
}

fn printf_is_shell_safe_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_' ||
  ch == '-' ||
  ch == '.' ||
  ch == '/' ||
  ch == ':' ||
  ch == '@'
}

fn printf_format_float(raw : String, precision : Int) -> String {
  let mut i = 0
  let mut negative = false
  if raw.length() > 0 {
    let first = raw[0].to_int().unsafe_to_char()
    if first == '-' {
      negative = true
      i = 1
    } else if first == '+' {
      i = 1
    }
  }

  let int_buf = StringBuilder::new()
  let frac_buf = StringBuilder::new()
  let mut in_frac = false
  while i < raw.length() {
    let ch = raw[i].to_int().unsafe_to_char()
    if ch == '.' {
      in_frac = true
      i += 1
      continue
    }
    if !(printf_is_digit(ch)) {
      break
    }
    if in_frac {
      frac_buf.write_char(ch)
    } else {
      int_buf.write_char(ch)
    }
    i += 1
  }

  let mut int_part = int_buf.to_string()
  if int_part.length() == 0 {
    int_part = "0"
  }
  let frac_part = frac_buf.to_string()

  if precision <= 0 {
    let mut rounded = int_part
    if frac_part.length() > 0 && frac_part[0].to_int().unsafe_to_char() >= '5' {
      rounded = printf_increment_digits(rounded)
    }
    if negative && rounded != "0" {
      "-" + rounded
    } else {
      rounded
    }
  } else {
    let mut frac_for_round = frac_part
    while frac_for_round.length() < precision + 1 {
      frac_for_round = frac_for_round + "0"
    }
    let keep = substring_slice(frac_for_round, 0, precision)
    let round_digit = frac_for_round[precision].to_int().unsafe_to_char()
    let mut out_int = int_part
    let mut out_frac = keep
    if round_digit >= '5' {
      let (next_frac, carry) = printf_increment_fraction(out_frac)
      out_frac = next_frac
      if carry {
        out_int = printf_increment_digits(out_int)
      }
    }
    let sign = if negative && !(out_int == "0" && printf_all_zeros(out_frac)) {
      "-"
    } else {
      ""
    }
    sign + out_int + "." + out_frac
  }
}

fn printf_increment_digits(digits : String) -> String {
  if digits.length() == 0 {
    return "1"
  }
  let chars : Array[Char] = []
  for i = 0; i < digits.length(); i = i + 1 {
    chars.push(digits[i].to_int().unsafe_to_char())
  }
  let mut carry = 1
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    let ch = chars[i]
    if ch < '0' || ch > '9' {
      continue
    }
    let sum = (ch.to_int() - '0'.to_int()) + carry
    if sum >= 10 {
      chars[i] = '0'
      carry = 1
    } else {
      chars[i] = (sum + '0'.to_int()).unsafe_to_char()
      carry = 0
      break
    }
    if i == 0 {
      break
    }
  }
  let out = StringBuilder::new()
  if carry == 1 {
    out.write_char('1')
  }
  for ch in chars {
    out.write_char(ch)
  }
  out.to_string()
}

fn printf_increment_fraction(frac : String) -> (String, Bool) {
  if frac.length() == 0 {
    return ("", true)
  }
  let chars : Array[Char] = []
  for i = 0; i < frac.length(); i = i + 1 {
    chars.push(frac[i].to_int().unsafe_to_char())
  }
  let mut carry = 1
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    let sum = (chars[i].to_int() - '0'.to_int()) + carry
    if sum >= 10 {
      chars[i] = '0'
      carry = 1
    } else {
      chars[i] = (sum + '0'.to_int()).unsafe_to_char()
      carry = 0
      break
    }
    if i == 0 {
      break
    }
  }
  let out = StringBuilder::new()
  for ch in chars {
    out.write_char(ch)
  }
  (out.to_string(), carry == 1)
}

fn printf_all_zeros(s : String) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int().unsafe_to_char() != '0' {
      return false
    }
  }
  true
}
