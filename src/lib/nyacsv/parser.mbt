// NyaCSV-compatible parser, adapted for current MoonBit compiler.

fn nyacsv_is_trim_char(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn nyacsv_trim_field(s : String) -> String {
  if s.length() == 0 {
    return ""
  }
  let mut start = 0
  while start < s.length() {
    let ch = s[start].to_int().unsafe_to_char()
    if not(nyacsv_is_trim_char(ch)) {
      break
    }
    start += 1
  }
  if start >= s.length() {
    return ""
  }
  let mut end_exclusive = s.length()
  while end_exclusive > start {
    let ch = s[end_exclusive - 1].to_int().unsafe_to_char()
    if not(nyacsv_is_trim_char(ch)) {
      break
    }
    end_exclusive -= 1
  }
  let out = StringBuilder::new()
  for i = start; i < end_exclusive; i = i + 1 {
    out.write_char(s[i].to_int().unsafe_to_char())
  }
  out.to_string()
}

fn nyacsv_finalize_field(field : StringBuilder, trim_spaces : Bool) -> String {
  let raw = field.to_string()
  if trim_spaces {
    nyacsv_trim_field(raw)
  } else {
    raw
  }
}

fn parse[T : CSVReader](
  reader : T,
  options~ : CSVOptions = {
    delimiter: ',',
    allow_newlines_in_quotes: true,
    quote_char: '"',
    skip_empty_lines: true,
    trim_spaces: false,
  }
) -> Array[Array[String]] {
  let rows : Array[Array[String]] = Array::new()
  let mut row : Array[String] = Array::new()
  let mut field = StringBuilder::new()
  let mut in_quotes = false

  while not(reader.is_eof()) {
    let mut ch = reader.read_char().unwrap()

    if ch == '\r' {
      if reader.peek_char() == Some('\n') {
        if in_quotes && options.allow_newlines_in_quotes {
          field.write_char(ch)
          reader.read_char() |> ignore
          field.write_char('\n')
          continue
        } else {
          continue
        }
      } else if options.allow_newlines_in_quotes && in_quotes {
        field.write_char(ch)
        continue
      } else {
        ch = '\n'
      }
    }

    if in_quotes {
      if ch == options.quote_char {
        if not(reader.is_eof()) &&
          reader.peek_char() == Some(options.quote_char) {
          field.write_char(options.quote_char)
          reader.read_char() |> ignore
        } else {
          in_quotes = false
        }
      } else if ch == '\n' && not(options.allow_newlines_in_quotes) {
        in_quotes = false
        row.push(nyacsv_finalize_field(field, options.trim_spaces))
        if not(row.is_empty()) || not(options.skip_empty_lines) {
          rows.push(row)
        }
        row = Array::new()
        field = StringBuilder::new()
      } else {
        field.write_char(ch)
      }
    } else if ch == options.quote_char {
      if field.is_empty() {
        in_quotes = true
      } else {
        field.write_char(ch)
      }
    } else if ch == options.delimiter {
      row.push(nyacsv_finalize_field(field, options.trim_spaces))
      field = StringBuilder::new()
    } else if ch == '\n' {
      row.push(nyacsv_finalize_field(field, options.trim_spaces))
      if not(row.is_empty()) || not(options.skip_empty_lines) {
        rows.push(row)
      }
      row = Array::new()
      field = StringBuilder::new()
    } else {
      field.write_char(ch)
    }
  }

  if not(field.is_empty()) || row.length() > 0 {
    row.push(nyacsv_finalize_field(field, options.trim_spaces))
    if not(row.is_empty()) || not(options.skip_empty_lines) {
      rows.push(row)
    }
  }

  rows
}
