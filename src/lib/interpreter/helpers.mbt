// moon_bash Interpreter - Common Helpers
// Shared utilities used across interpreter modules.

fn is_shell_builtin(name : String) -> Bool {
  match name {
    "export" | "unset" | "set" | "shift" | "exit" | "return" | "break"
    | "continue" | "read" | "test" | "[" | "[[" | "printf" | "eval" | "source"
    | "." | "local" | "readonly" | "declare" | "typeset" | "getopts" | "let" | ":" | "type" | "command" | "basename"
    | "dirname" | "seq" | "rev" | "nl" | "fold" | "expand" | "unexpand" | "paste"
    | "column" | "join" | "tr" | "sort" | "uniq" | "cut" | "tee" | "sed" | "grep"
    | "egrep" | "fgrep" | "rg" | "xargs" | "date" | "env" | "printenv"
    | "which" | "whoami" | "hostname" | "help" | "clear" | "history" | "tac"
    | "od" | "alias" | "unalias" | "bash" | "sh" | "time" | "sleep"
    | "timeout" | "mapfile" | "readarray" => true
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

// ============================================================================
// Test Evaluation
// ============================================================================

fn evaluate_test(args : Array[String], ctx : ExecContext) -> Bool {
  // Logical operators inside test/[ ... ].
  // Implement minimal precedence: -a binds tighter than -o.
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "-o" || args[i] == "||" {
      let left : Array[String] = []
      let right : Array[String] = []
      for j = 0; j < i; j = j + 1 {
        left.push(args[j])
      }
      for j = i + 1; j < args.length(); j = j + 1 {
        right.push(args[j])
      }
      return evaluate_test(left, ctx) || evaluate_test(right, ctx)
    }
  }
  for i = 0; i < args.length(); i = i + 1 {
    if args[i] == "-a" || args[i] == "&&" {
      let left : Array[String] = []
      let right : Array[String] = []
      for j = 0; j < i; j = j + 1 {
        left.push(args[j])
      }
      for j = i + 1; j < args.length(); j = j + 1 {
        right.push(args[j])
      }
      return evaluate_test(left, ctx) && evaluate_test(right, ctx)
    }
  }

  if args.length() == 0 {
    return false
  }
  if args[0] == "!" {
    let rest : Array[String] = []
    for i = 1; i < args.length(); i = i + 1 {
      rest.push(args[i])
    }
    return not(evaluate_test(rest, ctx))
  }
  if args.length() >= 3 && args[1] == "=~" {
    let left = args[0]
    let right = join_test_tokens(args, 2)
    return ctx.regex_cond_match(left, right)
  }
  if args.length() == 1 {
    // test STRING: true if string is non-empty
    return args[0].length() > 0
  }
  if args.length() == 2 {
    let op = args[0]
    let arg = args[1]
    match op {
      "-z" => return arg.length() == 0
      "-n" => return arg.length() > 0
      "-f" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(_)) => true
          _ => false
        }
      }
      "-d" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Directory(_)) => true
          _ => false
        }
      }
      "-e" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-s" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::File(data)) => data.content.length() > 0
          _ => false
        }
      }
      "-r" | "-w" | "-x" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return ctx.fs.exists(path)
      }
      "-L" | "-h" => {
        let path = try {
          @fs.resolve_path(ctx.cwd, arg)
        } catch {
          _ => return false
        }
        return match ctx.fs.entries.get(path) {
          Some(@fs.FsEntry::Symlink(_)) => true
          _ => false
        }
      }
      "-v" => return test_var_is_set(arg, ctx)
      "!" => return not(evaluate_test([arg], ctx))
      _ => ()
    }
  }
  if args.length() == 3 {
    let left = args[0]
    let op = args[1]
    let right = args[2]
    match op {
      "=" | "==" => return test_string_compare(left, right)
      "!=" => return not(test_string_compare(left, right))
      "=~" => return ctx.regex_cond_match(left, right)
      "-eq" => return parse_int_str(left) == parse_int_str(right)
      "-ne" => return parse_int_str(left) != parse_int_str(right)
      "-lt" => return parse_int_str(left) < parse_int_str(right)
      "-le" => return parse_int_str(left) <= parse_int_str(right)
      "-gt" => return parse_int_str(left) > parse_int_str(right)
      "-ge" => return parse_int_str(left) >= parse_int_str(right)
      "-nt" | "-ot" | "-ef" => return false // File comparison not meaningful in sandbox
      _ => ()
    }
  }
  false
}

fn join_test_tokens(args : Array[String], start : Int) -> String {
  let out = StringBuilder::new()
  for i = start; i < args.length(); i = i + 1 {
    out.write_string(args[i])
  }
  out.to_string()
}

fn test_var_is_set(name : String, ctx : ExecContext) -> Bool {
  match parse_array_reference_name(name) {
    Some((base, index)) => {
      if index == "@" || index == "*" {
        ctx.env.contains(base) || ctx.env.contains(base + "[@]")
      } else {
        ctx.env.contains("\{base}[\{index}]")
      }
    }
    None => ctx.env.contains(name)
  }
}

fn test_string_compare(left : String, right : String) -> Bool {
  if has_glob_meta(right) {
    simple_pattern_match(left, right)
  } else {
    left == right
  }
}

// ============================================================================
// Printf Implementation
// ============================================================================

fn format_printf(format : String, args : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  let mut arg_idx = 0

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
          if not(printf_is_octal_digit(oct_ch)) {
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
        if not(printf_is_digit(digit)) {
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
          if not(printf_is_digit(digit)) {
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
        not(left_justify) &&
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
    if not(printf_is_shell_safe_char(ch)) {
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
    if not(printf_is_digit(ch)) {
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
    let sign = if negative && not(out_int == "0" && printf_all_zeros(out_frac)) {
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
