// NyaCSV-compatible public API, vendored for compiler compatibility.

pub struct CSV {
  headers : Array[String]
  rows : Array[Array[String]]
}

pub fn CSV::header(self : CSV) -> Array[String] {
  self.headers
}

pub fn CSV::data(self : CSV) -> Array[Array[String]] {
  self.rows
}

pub fn CSV::shape(self : CSV) -> (Int, Int) {
  let row_count = self.rows.length()
  let column_count = if row_count > 0 { self.rows[0].length() } else { 0 }
  (row_count, column_count)
}

pub fn CSV::new() -> CSV {
  let headers : Array[String] = Array::new()
  let rows : Array[Array[String]] = Array::new()
  { headers, rows }
}

pub fn CSV::from_array(
  data : Array[Array[String]],
  has_header~ : Bool = true,
  generate_headers~ : Bool = true
) -> CSV {
  if data.is_empty() {
    return CSV::new()
  }

  if has_header {
    let headers = data[0]
    let rows : Array[Array[String]] = Array::new()
    for i = 1; i < data.length(); i = i + 1 {
      rows.push(data[i])
    }
    return { headers, rows }
  }

  if generate_headers {
    let column_count = data[0].length()
    let headers : Array[String] = Array::new()
    for i = 0; i < column_count; i = i + 1 {
      headers.push("column\{i + 1}")
    }
    return { headers, rows: data }
  }

  let column_count = data[0].length()
  let headers : Array[String] = Array::new()
  for _i = 0; _i < column_count; _i = _i + 1 {
    headers.push("")
  }
  { headers, rows: data }
}

pub fn CSV::parse_string(
  data : String,
  options~ : CSVOptions = {
    delimiter: ',',
    allow_newlines_in_quotes: true,
    quote_char: '"',
    skip_empty_lines: true,
    trim_spaces: false,
  }
) -> CSV {
  let reader : StringReader = { source: data, pos: 0 }
  CSV::from_array(parse(reader, options~))
}

pub fn CSV::parse_buffer(
  data : @buffer.T,
  options~ : CSVOptions = {
    delimiter: ',',
    allow_newlines_in_quotes: true,
    quote_char: '"',
    skip_empty_lines: true,
    trim_spaces: false,
  }
) -> CSV {
  let reader : StringReader = {
    source: data.contents().to_unchecked_string(),
    pos: 0,
  }
  CSV::from_array(parse(reader, options~))
}

pub fn CSV::parse_bytes(
  data : Bytes,
  options~ : CSVOptions = {
    delimiter: ',',
    allow_newlines_in_quotes: true,
    quote_char: '"',
    skip_empty_lines: true,
    trim_spaces: false,
  }
) -> CSV {
  let reader : StringReader = { source: data.to_unchecked_string(), pos: 0 }
  CSV::from_array(parse(reader, options~))
}
