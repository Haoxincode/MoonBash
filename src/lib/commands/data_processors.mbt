// moon_bash Commands - Data Processors
// yq (YAML processor), xan/csvlook (CSV processors)

/// Convert a Yaml value to a JSON string
fn yaml_to_json_string(y : @yaml.Yaml) -> String {
  y.to_json().stringify()
}

/// Apply a yq filter expression to a Yaml value.
/// Supports: ".", ".key", ".key.subkey", ".[N]", ".[]"
fn yq_apply_filter(
  y : @yaml.Yaml,
  filter : String
) -> (@yaml.Yaml, Bool) {
  // identity filter
  if filter == "." {
    return (y, false)
  }
  // Parse the filter into segments
  let segments = yq_parse_filter(filter)
  let mut current = y
  let mut iterate_array = false
  for seg in segments {
    match seg {
      "[]" => {
        iterate_array = true
        // don't descend further, handled in output
        break
      }
      _ => {
        // Check if it's an array index like [N]
        if seg.has_prefix("[") && seg.has_suffix("]") {
          let idx_str = cmd_substr_slice(seg, 1, seg.length() - 1)
          let idx = cmd_parse_int(idx_str)
          match current {
            @yaml.Yaml::Array(arr) =>
              if idx >= 0 && idx < arr.length() {
                current = arr[idx]
              } else {
                current = @yaml.Yaml::Null
              }
            _ => { current = @yaml.Yaml::Null }
          }
        } else {
          // Map key access
          match current {
            @yaml.Yaml::Map(m) =>
              match m.get(seg) {
                Some(v) => current = v
                None => { current = @yaml.Yaml::Null }
              }
            _ => { current = @yaml.Yaml::Null }
          }
        }
      }
    }
  }
  (current, iterate_array)
}

/// Parse a filter string like ".key.subkey.[0].[]" into segments
fn yq_parse_filter(filter : String) -> Array[String] {
  let segments : Array[String] = []
  let buf = StringBuilder::new()
  let mut i = 0
  // Skip leading dot
  if filter.length() > 0 && filter[0] == '.' {
    i = 1
  }
  while i < filter.length() {
    let ch = filter[i].to_int().unsafe_to_char()
    if ch == '.' {
      let s = buf.to_string()
      if s.length() > 0 {
        segments.push(s)
      }
      buf.reset()
      i += 1
    } else if ch == '[' {
      // Flush any pending key
      let s = buf.to_string()
      if s.length() > 0 {
        segments.push(s)
        buf.reset()
      }
      // Collect bracket content including brackets
      let bracket_buf = StringBuilder::new()
      bracket_buf.write_char('[')
      i += 1
      while i < filter.length() {
        let c2 = filter[i].to_int().unsafe_to_char()
        if c2 == ']' {
          bracket_buf.write_char(']')
          i += 1
          break
        }
        bracket_buf.write_char(c2)
        i += 1
      }
      segments.push(bracket_buf.to_string())
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  let s = buf.to_string()
  if s.length() > 0 {
    segments.push(s)
  }
  segments
}

/// Format a Yaml value for output, with optional raw mode
fn yq_format_output(y : @yaml.Yaml, raw : Bool) -> String {
  if raw {
    match y {
      @yaml.Yaml::String(s) => s
      @yaml.Yaml::Null => "null"
      _ => yaml_to_json_string(y)
    }
  } else {
    yaml_to_json_string(y)
  }
}

/// yq: YAML processor command
fn cmd_yq(ctx : CommandContext) -> @ast.ExecResult {
  let mut raw = false
  let mut filter = "."
  let mut file_path : String? = None
  let mut i = 0

  // Parse arguments
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-r" {
      raw = true
      i += 1
    } else if arg == "-j" {
      // JSON output is default, just consume the flag
      i += 1
    } else if arg.has_prefix("-") && arg.length() > 1 {
      // Unknown flag, skip
      i += 1
    } else if (filter == "." && arg.has_prefix(".")) || arg == "." {
      // First non-flag argument starting with . is the filter
      filter = arg
      i += 1
    } else {
      // File path
      file_path = Some(arg)
      i += 1
    }
  }

  // Read input
  let content = match file_path {
    Some(p) => {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, p)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("yq: \{msg}\n")
      }
      try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("yq: \{msg}\n")
      }
    }
    None => ctx.stdin_content
  }

  if content.length() == 0 {
    return @ast.ExecResult::err("yq: empty input\n")
  }

  // Parse YAML
  let docs : Array[@yaml.Yaml] = try {
    @yaml.Yaml::load_from_string(content[:])
  } catch {
    @yaml.YamlError(_) as e => return @ast.ExecResult::err("yq: \{e}\n")
  }

  if docs.length() == 0 {
    return @ast.ExecResult::err("yq: no YAML documents found\n")
  }

  let doc = docs[0]
  let (result, iterate) = yq_apply_filter(doc, filter)
  let out = StringBuilder::new()

  if iterate {
    match result {
      @yaml.Yaml::Array(arr) =>
        for item in arr {
          out.write_string(yq_format_output(item, raw))
          out.write_char('\n')
        }
      _ => {
        out.write_string(yq_format_output(result, raw))
        out.write_char('\n')
      }
    }
  } else {
    out.write_string(yq_format_output(result, raw))
    out.write_char('\n')
  }

  @ast.ExecResult::ok(out.to_string())
}

/// xan: CSV processor command
fn cmd_xan(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    // No args at all - read stdin and pretty-print
    if ctx.stdin_content.length() == 0 {
      return @ast.ExecResult::err("xan: missing subcommand or file\n")
    }
    let csv = @nyacsv.CSV::parse_string(ctx.stdin_content)
    return @ast.ExecResult::ok(xan_view(csv))
  }

  let subcmd = ctx.args[0]

  // If the first arg doesn't look like a subcommand, treat it as a file
  match subcmd {
    "headers" => xan_headers(ctx)
    "select" => xan_select(ctx)
    "slice" => xan_slice(ctx)
    "view" => xan_view_cmd(ctx)
    "count" => xan_count(ctx)
    _ => {
      // Treat first arg as a file, default to view
      let resolved = try {
        @fs.resolve_path(ctx.cwd, subcmd)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("xan: \{msg}\n")
      }
      let content = try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("xan: \{msg}\n")
      }
      let csv = @nyacsv.CSV::parse_string(content)
      @ast.ExecResult::ok(xan_view(csv))
    }
  }
}

/// csvlook: pretty-print CSV as a table (xan view-compatible).
fn cmd_csvlook(ctx : CommandContext) -> @ast.ExecResult {
  let content = if ctx.args.length() > 0 {
    let path = ctx.args[0]
    if path == "-" {
      ctx.stdin_content
    } else {
      let resolved = try {
        @fs.resolve_path(ctx.cwd, path)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("csvlook: \{msg}\n")
      }
      try {
        ctx.fs.read_file(resolved)
      } catch {
        @fs.FsError(msg) => return @ast.ExecResult::err("csvlook: \{msg}\n")
      }
    }
  } else {
    ctx.stdin_content
  }

  if content.length() == 0 {
    return @ast.ExecResult::err("csvlook: missing input\n")
  }

  let csv = @nyacsv.CSV::parse_string(content)
  @ast.ExecResult::ok(xan_view(csv))
}

/// xan headers: list column names one per line
fn xan_headers(ctx : CommandContext) -> @ast.ExecResult {
  let content = xan_get_input(ctx, 1)
  match content {
    Err(msg) => @ast.ExecResult::err(msg)
    Ok(data) => {
      let csv = @nyacsv.CSV::parse_string(data)
      let out = StringBuilder::new()
      let headers = csv.header()
      for i = 0; i < headers.length(); i = i + 1 {
        out.write_string(headers[i])
        out.write_char('\n')
      }
      @ast.ExecResult::ok(out.to_string())
    }
  }
}

/// xan select COL1,COL2 file.csv: select specific columns
fn xan_select(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() < 2 {
    return @ast.ExecResult::err("xan select: missing column specification\n")
  }
  let col_spec = ctx.args[1]
  let col_names = xan_split_col_spec(col_spec)
  let content = xan_get_input(ctx, 2)
  match content {
    Err(msg) => @ast.ExecResult::err(msg)
    Ok(data) => {
      let csv = @nyacsv.CSV::parse_string(data)
      let headers = csv.header()
      // Find column indices
      let indices : Array[Int] = []
      for name in col_names {
        let mut found = -1
        for j = 0; j < headers.length(); j = j + 1 {
          if headers[j] == name {
            found = j
            break
          }
        }
        if found >= 0 {
          indices.push(found)
        }
      }
      if indices.length() == 0 {
        return @ast.ExecResult::err("xan select: no matching columns found\n")
      }
      let out = StringBuilder::new()
      // Output selected headers
      for i = 0; i < indices.length(); i = i + 1 {
        if i > 0 {
          out.write_char(',')
        }
        out.write_string(headers[indices[i]])
      }
      out.write_char('\n')
      // Output selected data
      let rows = csv.data()
      for row in rows {
        for i = 0; i < indices.length(); i = i + 1 {
          if i > 0 {
            out.write_char(',')
          }
          let idx = indices[i]
          if idx < row.length() {
            out.write_string(row[idx])
          }
        }
        out.write_char('\n')
      }
      @ast.ExecResult::ok(out.to_string())
    }
  }
}

/// xan slice -i START -l LENGTH file.csv: slice rows
fn xan_slice(ctx : CommandContext) -> @ast.ExecResult {
  let mut start = 0
  let mut length : Int? = None
  let mut file_idx = -1
  let mut i = 1
  while i < ctx.args.length() {
    if ctx.args[i] == "-i" && i + 1 < ctx.args.length() {
      start = cmd_parse_int(ctx.args[i + 1])
      i += 2
    } else if ctx.args[i] == "-l" && i + 1 < ctx.args.length() {
      length = Some(cmd_parse_int(ctx.args[i + 1]))
      i += 2
    } else if not(ctx.args[i].has_prefix("-")) {
      file_idx = i
      i += 1
    } else {
      i += 1
    }
  }
  let content = if file_idx >= 0 {
    let resolved = try {
      @fs.resolve_path(ctx.cwd, ctx.args[file_idx])
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("xan slice: \{msg}\n")
    }
    try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return @ast.ExecResult::err("xan slice: \{msg}\n")
    }
  } else {
    ctx.stdin_content
  }
  let csv = @nyacsv.CSV::parse_string(content)
  let headers = csv.header()
  let rows = csv.data()
  let end = match length {
    Some(l) => {
      let e = start + l
      if e > rows.length() { rows.length() } else { e }
    }
    None => rows.length()
  }
  let actual_start = if start < 0 { 0 } else if start > rows.length() { rows.length() } else { start }
  let out = StringBuilder::new()
  // Output headers
  out.write_string(headers.join(","))
  out.write_char('\n')
  // Output sliced rows
  for j = actual_start; j < end; j = j + 1 {
    out.write_string(rows[j].join(","))
    out.write_char('\n')
  }
  @ast.ExecResult::ok(out.to_string())
}

/// xan view: pretty-print CSV as a table
fn xan_view_cmd(ctx : CommandContext) -> @ast.ExecResult {
  let content = xan_get_input(ctx, 1)
  match content {
    Err(msg) => @ast.ExecResult::err(msg)
    Ok(data) => {
      let csv = @nyacsv.CSV::parse_string(data)
      @ast.ExecResult::ok(xan_view(csv))
    }
  }
}

/// xan count: count data rows
fn xan_count(ctx : CommandContext) -> @ast.ExecResult {
  let content = xan_get_input(ctx, 1)
  match content {
    Err(msg) => @ast.ExecResult::err(msg)
    Ok(data) => {
      let csv = @nyacsv.CSV::parse_string(data)
      let (row_count, _) = csv.shape()
      @ast.ExecResult::ok(row_count.to_string() + "\n")
    }
  }
}

/// Helper: get input for xan subcommands (file arg at position arg_start, or stdin)
fn xan_get_input(ctx : CommandContext, arg_start : Int) -> Result[String, String] {
  if arg_start < ctx.args.length() {
    let path = ctx.args[arg_start]
    if path == "-" {
      return Ok(ctx.stdin_content)
    }
    let resolved = try {
      @fs.resolve_path(ctx.cwd, path)
    } catch {
      @fs.FsError(msg) => return Err("xan: \{msg}\n")
    }
    let data = try {
      ctx.fs.read_file(resolved)
    } catch {
      @fs.FsError(msg) => return Err("xan: \{msg}\n")
    }
    Ok(data)
  } else {
    Ok(ctx.stdin_content)
  }
}

/// Split comma-separated column spec (e.g. "a,b,c") into column names.
fn xan_split_col_spec(spec : String) -> Array[String] {
  let parts : Array[String] = []
  let current = StringBuilder::new()
  for i = 0; i < spec.length(); i = i + 1 {
    let ch = spec[i].to_int().unsafe_to_char()
    if ch == ',' {
      parts.push(current.to_string())
      current.reset()
    } else {
      current.write_char(ch)
    }
  }
  parts.push(current.to_string())
  parts
}

/// Pretty-print a CSV as an aligned table
fn xan_view(csv : @nyacsv.CSV) -> String {
  let headers = csv.header()
  let rows = csv.data()
  if headers.length() == 0 {
    return ""
  }
  // Calculate column widths
  let widths : Array[Int] = Array::make(headers.length(), 0)
  for i = 0; i < headers.length(); i = i + 1 {
    widths[i] = headers[i].length()
  }
  for row in rows {
    for i = 0; i < headers.length(); i = i + 1 {
      if i < row.length() {
        let val = row[i].replace(old="\n", new="\\n")
        if val.length() > widths[i] {
          widths[i] = val.length()
        }
      }
    }
  }
  let out = StringBuilder::new()
  // Top border
  xan_draw_border(out, widths)
  // Header row
  out.write_char('|')
  for i = 0; i < headers.length(); i = i + 1 {
    out.write_char(' ')
    out.write_string(headers[i])
    xan_pad(out, widths[i] - headers[i].length())
    out.write_string(" |")
  }
  out.write_char('\n')
  // Separator
  xan_draw_border(out, widths)
  // Data rows
  for row in rows {
    out.write_char('|')
    for i = 0; i < headers.length(); i = i + 1 {
      let raw_val = if i < row.length() { row[i] } else { "" }
      let val = raw_val.replace(old="\n", new="\\n")
      out.write_char(' ')
      out.write_string(val)
      xan_pad(out, widths[i] - val.length())
      out.write_string(" |")
    }
    out.write_char('\n')
  }
  // Bottom border
  xan_draw_border(out, widths)
  out.to_string()
}

/// Draw a table border line
fn xan_draw_border(out : StringBuilder, widths : Array[Int]) -> Unit {
  out.write_char('+')
  for w in widths {
    for _j = 0; _j < w + 2; _j = _j + 1 {
      out.write_char('-')
    }
    out.write_char('+')
  }
  out.write_char('\n')
}

/// Write padding spaces
fn xan_pad(out : StringBuilder, count : Int) -> Unit {
  for _i = 0; _i < count; _i = _i + 1 {
    out.write_char(' ')
  }
}
