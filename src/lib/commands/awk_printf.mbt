// moon_bash Commands - awk printf formatting

fn awk_split_csv_args(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  let mut quote : Char? = None
  let mut paren_depth = 0
  let mut bracket_depth = 0
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        buf.write_char(ch)
        if ch == q {
          quote = None
        }
      }
      None => {
        if ch == '"' || ch == '\'' {
          quote = Some(ch)
          buf.write_char(ch)
        } else if ch == '(' {
          paren_depth += 1
          buf.write_char(ch)
        } else if ch == ')' {
          if paren_depth > 0 {
            paren_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == '[' {
          bracket_depth += 1
          buf.write_char(ch)
        } else if ch == ']' {
          if bracket_depth > 0 {
            bracket_depth -= 1
          }
          buf.write_char(ch)
        } else if ch == ',' && paren_depth == 0 && bracket_depth == 0 {
          parts.push(aj_trim(buf.to_string()))
          buf.reset()
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  let last = aj_trim(buf.to_string())
  if last.length() > 0 {
    parts.push(last)
  }
  parts
}

fn awk_parse_printf(action : String) -> (String, Array[String]) {
  let mut rest = aj_trim(aj_substr(action, 6, action.length()))
  if rest.length() == 0 {
    return ("", [])
  }
  if rest.length() >= 2 &&
    rest[0].to_int().unsafe_to_char() == '(' &&
    rest[rest.length() - 1].to_int().unsafe_to_char() == ')' {
    rest = aj_trim(aj_substr(rest, 1, rest.length() - 1))
  }
  let args = awk_split_csv_args(rest)
  if args.length() == 0 {
    return ("", [])
  }
  let tail : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    tail.push(args[i])
  }
  (args[0], tail)
}

fn awk_pow10_int(exp : Int) -> Int {
  let mut out = 1
  let mut i = 0
  let limit = if exp < 0 { 0 } else if exp > 9 { 9 } else { exp }
  while i < limit {
    out *= 10
    i += 1
  }
  out
}

fn awk_to_hex_string(value : Int) -> String {
  if value == 0 {
    return "0"
  }
  let hex = "0123456789abcdef"
  let chars : Array[Char] = []
  let mut v = if value < 0 { -value } else { value }
  while v > 0 {
    let digit = v % 16
    chars.push(hex[digit].to_int().unsafe_to_char())
    v /= 16
  }
  let out = StringBuilder::new()
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    out.write_char(chars[i])
  }
  out.to_string()
}

fn awk_pad_left(text : String, width : Int, pad : Char) -> String {
  if width <= text.length() {
    return text
  }
  let out = StringBuilder::new()
  let mut remaining = width - text.length()
  while remaining > 0 {
    out.write_char(pad)
    remaining -= 1
  }
  out.write_string(text)
  out.to_string()
}

fn awk_pad_right(text : String, width : Int, pad : Char) -> String {
  if width <= text.length() {
    return text
  }
  let out = StringBuilder::new()
  out.write_string(text)
  let mut remaining = width - text.length()
  while remaining > 0 {
    out.write_char(pad)
    remaining -= 1
  }
  out.to_string()
}

fn awk_apply_printf_width(
  text : String,
  width : Int,
  left_align : Bool,
  zero_pad : Bool
) -> String {
  if width <= text.length() {
    return text
  }
  if left_align {
    return awk_pad_right(text, width, ' ')
  }
  if zero_pad && text.length() > 0 {
    let first = text[0].to_int().unsafe_to_char()
    if first == '+' || first == '-' || first == ' ' {
      return first.to_string() + awk_pad_left(aj_substr(text, 1, text.length()), width - 1, '0')
    }
  }
  awk_pad_left(text, width, if zero_pad { '0' } else { ' ' })
}

fn awk_format_fixed_number(
  raw : Double,
  precision : Int,
  plus_sign : Bool,
  space_sign : Bool
) -> String {
  let mut precision = precision
  if precision < 0 {
    precision = 6
  } else if precision > 9 {
    precision = 9
  }
  let scale = @math.pow(10.0, precision.to_double())
  let rounded = if raw >= 0.0 {
    (raw * scale + 0.5).to_int()
  } else {
    (raw * scale - 0.5).to_int()
  }
  let negative = rounded < 0
  let abs_scaled = if rounded < 0 { -rounded } else { rounded }
  let pow10 = awk_pow10_int(precision)
  let whole = if precision == 0 { abs_scaled } else { abs_scaled / pow10 }
  let frac = if precision == 0 { 0 } else { abs_scaled % pow10 }
  let sign = if negative {
    "-"
  } else if plus_sign {
    "+"
  } else if space_sign {
    " "
  } else {
    ""
  }
  if precision == 0 {
    return sign + whole.to_string()
  }
  let frac_text = frac.to_string()
  let frac_padded = awk_pad_left(frac_text, precision, '0')
  sign + whole.to_string() + "." + frac_padded
}

fn awk_trim_trailing_fraction_zeros(text : String) -> String {
  let dot = aj_index_of(text, '.')
  if dot < 0 {
    return text
  }
  let mut end_ = text.length()
  while end_ > dot + 1 && text[end_ - 1].to_int().unsafe_to_char() == '0' {
    end_ -= 1
  }
  if end_ == dot + 1 {
    end_ -= 1
  }
  aj_substr(text, 0, end_)
}

fn awk_format_printf(format : String, args : Array[String]) -> String {
  let decoded = aj_decode_c_escapes(format)
  let out = StringBuilder::new()
  let mut arg_idx = 0
  let mut i = 0
  while i < decoded.length() {
    let ch = decoded[i].to_int().unsafe_to_char()
    if ch == '%' {
      if i + 1 < decoded.length() && decoded[i + 1].to_int().unsafe_to_char() == '%' {
        out.write_char('%')
        i += 2
        continue
      }
      let mut j = i + 1
      let mut left_align = false
      let mut plus_sign = false
      let mut space_sign = false
      let mut zero_pad = false
      while j < decoded.length() {
        let f = decoded[j].to_int().unsafe_to_char()
        if f == '-' {
          left_align = true
          j += 1
        } else if f == '+' {
          plus_sign = true
          j += 1
        } else if f == ' ' {
          space_sign = true
          j += 1
        } else if f == '0' {
          zero_pad = true
          j += 1
        } else {
          break
        }
      }
      let mut width = 0
      if j < decoded.length() && decoded[j].to_int().unsafe_to_char() == '*' {
        width = if arg_idx < args.length() { awk_parse_number(args[arg_idx]).to_int() } else { 0 }
        arg_idx += 1
        j += 1
      } else {
        while j < decoded.length() {
          let wch = decoded[j].to_int().unsafe_to_char()
          if wch >= '0' && wch <= '9' {
            width = width * 10 + (wch.to_int() - '0'.to_int())
            j += 1
          } else {
            break
          }
        }
      }
      if width < 0 {
        left_align = true
        width = -width
      }
      if width > 10000 {
        width = 10000
      }
      let mut precision = -1
      if j < decoded.length() && decoded[j].to_int().unsafe_to_char() == '.' {
        j += 1
        if j < decoded.length() && decoded[j].to_int().unsafe_to_char() == '*' {
          precision = if arg_idx < args.length() { awk_parse_number(args[arg_idx]).to_int() } else { 0 }
          arg_idx += 1
          j += 1
        } else {
          precision = 0
          while j < decoded.length() {
            let pch = decoded[j].to_int().unsafe_to_char()
            if pch >= '0' && pch <= '9' {
              precision = precision * 10 + (pch.to_int() - '0'.to_int())
              j += 1
            } else {
              break
            }
          }
        }
        if precision > 1000 {
          precision = 1000
        }
      }
      if j >= decoded.length() {
        out.write_char('%')
        i += 1
        continue
      }
      let spec = decoded[j].to_int().unsafe_to_char()
      let raw = if arg_idx < args.length() { args[arg_idx] } else { "" }
      if spec == 's' {
        let mut value = raw
        if precision >= 0 && precision < value.length() {
          value = aj_substr(value, 0, precision)
        }
        out.write_string(awk_apply_printf_width(value, width, left_align, false))
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'd' || spec == 'i' {
        let num = awk_parse_number(raw).to_int()
        let negative = num < 0
        let mut digits = if num < 0 { (-num).to_string() } else { num.to_string() }
        if precision == 0 && num == 0 {
          digits = ""
        }
        if precision > 0 {
          digits = awk_pad_left(digits, precision, '0')
        }
        let sign = if negative {
          "-"
        } else if plus_sign {
          "+"
        } else if space_sign {
          " "
        } else {
          ""
        }
        let text = sign + digits
        out.write_string(
          awk_apply_printf_width(text, width, left_align, zero_pad && precision < 0),
        )
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'x' || spec == 'X' {
        let num = awk_parse_number(raw).to_int()
        let mut digits = awk_to_hex_string(num)
        if precision == 0 && num == 0 {
          digits = ""
        }
        if precision > 0 {
          digits = awk_pad_left(digits, precision, '0')
        }
        if spec == 'X' {
          digits = awk_to_upper(digits)
        }
        out.write_string(
          awk_apply_printf_width(digits, width, left_align, zero_pad && precision < 0),
        )
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'f' || spec == 'F' {
        let num = awk_parse_number(raw)
        let text = awk_format_fixed_number(
          num,
          if precision >= 0 { precision } else { 6 },
          plus_sign,
          space_sign,
        )
        out.write_string(awk_apply_printf_width(text, width, left_align, zero_pad && precision < 0))
        arg_idx += 1
        i = j + 1
        continue
      }
      if spec == 'g' || spec == 'G' {
        let num = awk_parse_number(raw)
        let mut text = awk_format_fixed_number(
          num,
          if precision > 0 { precision } else { 6 },
          plus_sign,
          space_sign,
        )
        text = awk_trim_trailing_fraction_zeros(text)
        if spec == 'G' {
          text = awk_to_upper(text)
        }
        out.write_string(awk_apply_printf_width(text, width, left_align, false))
        arg_idx += 1
        i = j + 1
        continue
      }
      out.write_char('%')
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

