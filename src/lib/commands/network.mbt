// MoonBash Commands - Network
// curl, html-to-markdown

priv struct NetFetchResponse {
  ok : Bool
  status : Int
  status_text : String
  body : String
  error : String
  headers : Array[(String, String)]
}

fn net_hex_digit(n : Int) -> Char {
  if n < 10 {
    (n + 48).unsafe_to_char()
  } else {
    (n - 10 + 97).unsafe_to_char()
  }
}

fn net_json_escape_string(s : String) -> String {
  let out = StringBuilder::new()
  out.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    match ch {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ => {
        let code = ch.to_int()
        if code < 0x20 {
          out.write_string("\\u00")
          out.write_char(net_hex_digit(code / 16))
          out.write_char(net_hex_digit(code % 16))
        } else {
          out.write_char(ch)
        }
      }
    }
  }
  out.write_char('"')
  out.to_string()
}

fn net_headers_to_json(headers : Array[(String, String)]) -> String {
  let out = StringBuilder::new()
  out.write_char('{')
  for i = 0; i < headers.length(); i = i + 1 {
    if i > 0 {
      out.write_char(',')
    }
    let (k, v) = headers[i]
    out.write_string(net_json_escape_string(k))
    out.write_char(':')
    out.write_string(net_json_escape_string(v))
  }
  out.write_char('}')
  out.to_string()
}

fn net_build_fetch_request_json(
  url : String,
  http_method : String,
  headers : Array[(String, String)],
  body : String?
) -> String {
  let out = StringBuilder::new()
  out.write_char('{')
  out.write_string("\"url\":")
  out.write_string(net_json_escape_string(url))
  out.write_string(",\"method\":")
  out.write_string(net_json_escape_string(http_method))
  out.write_string(",\"headers\":")
  out.write_string(net_headers_to_json(headers))
  match body {
    Some(content) => {
      out.write_string(",\"body\":")
      out.write_string(net_json_escape_string(content))
    }
    None => ()
  }
  out.write_char('}')
  out.to_string()
}

fn net_json_get_string(
  obj : Map[String, Json],
  key : String,
  default_value : String
) -> String {
  match obj.get(key) {
    Some(Json::String(s)) => s
    Some(Json::Number(n, ..)) => n.to_int().to_string()
    Some(Json::True) => "true"
    Some(Json::False) => "false"
    Some(Json::Null) => ""
    _ => default_value
  }
}

fn net_json_get_int(
  obj : Map[String, Json],
  key : String,
  default_value : Int
) -> Int {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    Some(Json::String(s)) => cmd_parse_int(s)
    _ => default_value
  }
}

fn net_json_get_bool(
  obj : Map[String, Json],
  key : String,
  default_value : Bool
) -> Bool {
  match obj.get(key) {
    Some(Json::True) => true
    Some(Json::False) => false
    Some(Json::String("true")) => true
    Some(Json::String("false")) => false
    _ => default_value
  }
}

fn net_json_get_headers(obj : Map[String, Json]) -> Array[(String, String)] {
  match obj.get("headers") {
    Some(Json::Object(headers_obj)) => {
      let headers : Array[(String, String)] = []
      for key, value in headers_obj {
        let text = match value {
          Json::String(s) => s
          Json::Number(n, ..) => n.to_int().to_string()
          Json::True => "true"
          Json::False => "false"
          Json::Null => ""
          _ => value.stringify(indent=0)
        }
        headers.push((key, text))
      }
      headers.sort_by(fn(a, b) {
        if a.0 < b.0 {
          -1
        } else if a.0 > b.0 {
          1
        } else {
          0
        }
      })
      headers
    }
    _ => []
  }
}

fn net_parse_fetch_response(json_str : String) -> Result[NetFetchResponse, String] {
  let parsed = try {
    @json.parse(json_str[:])
  } catch {
    _ => return Err("fetch bridge returned invalid JSON")
  }
  match parsed {
    Json::Object(obj) => {
      let status_text = net_json_get_string(
        obj,
        "statusText",
        net_json_get_string(obj, "status_text", ""),
      )
      Ok({
        ok: net_json_get_bool(obj, "ok", false),
        status: net_json_get_int(obj, "status", 0),
        status_text,
        body: net_json_get_string(obj, "body", ""),
        error: net_json_get_string(obj, "error", ""),
        headers: net_json_get_headers(obj),
      })
    }
    _ => Err("fetch bridge returned a non-object payload")
  }
}

fn net_fetch_url(
  url : String,
  http_method : String,
  headers : Array[(String, String)],
  body : String?
) -> Result[NetFetchResponse, String] {
  let request_json = net_build_fetch_request_json(url, http_method, headers, body)
  let raw = @ffi.fetch_sync(request_json)
  let response = match net_parse_fetch_response(raw) {
    Err(msg) => return Err(msg)
    Ok(r) => r
  }
  if not(response.ok) && response.status == 0 && response.error.length() == 0 {
    return Err("network request failed")
  }
  if response.error.length() > 0 {
    return Err(response.error)
  }
  Ok(response)
}

fn net_write_output_file(
  ctx : CommandContext,
  cmd_name : String,
  raw_path : String,
  content : String
) -> String? {
  let path = try {
    @fs.resolve_path(ctx.cwd, raw_path)
  } catch {
    @fs.FsError(msg) => return Some("\{cmd_name}: \{msg}\n")
  }
  try {
    ctx.fs.write_file(path, content)
  } catch {
    @fs.FsError(msg) => return Some("\{cmd_name}: \{msg}\n")
  }
  None
}

fn net_ascii_upper(s : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'a' && ch <= 'z' {
      out.write_char((ch.to_int() - 32).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

fn net_ascii_lower(s : String) -> String {
  let out = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if ch >= 'A' && ch <= 'Z' {
      out.write_char((ch.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

fn net_is_whitespace(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn net_trim(s : String) -> String {
  let mut start = 0
  let mut end_ = s.length()
  while start < end_ {
    let ch = s[start].to_int().unsafe_to_char()
    if net_is_whitespace(ch) {
      start += 1
    } else {
      break
    }
  }
  while end_ > start {
    let ch = s[end_ - 1].to_int().unsafe_to_char()
    if net_is_whitespace(ch) {
      end_ -= 1
    } else {
      break
    }
  }
  cmd_substr_slice(s, start, end_)
}

fn net_index_of_from(s : String, needle : String, start : Int) -> Int {
  if needle.length() == 0 {
    return start
  }
  if start < 0 {
    return -1
  }
  if needle.length() > s.length() {
    return -1
  }
  let limit = s.length() - needle.length()
  let mut i = start
  while i <= limit {
    let mut matched = true
    for j = 0; j < needle.length(); j = j + 1 {
      if s[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
    i += 1
  }
  -1
}

fn net_index_of_char(s : String, target : Char, start : Int) -> Int {
  let mut i = start
  while i < s.length() {
    if s[i].to_int().unsafe_to_char() == target {
      return i
    }
    i += 1
  }
  -1
}

fn net_replace_all(s : String, old : String, new_ : String) -> String {
  if old.length() == 0 {
    return s
  }
  let out = StringBuilder::new()
  let mut cursor = 0
  while cursor < s.length() {
    let idx = net_index_of_from(s, old, cursor)
    if idx < 0 {
      out.write_string(cmd_substr_slice(s, cursor, s.length()))
      break
    }
    out.write_string(cmd_substr_slice(s, cursor, idx))
    out.write_string(new_)
    cursor = idx + old.length()
  }
  out.to_string()
}

fn net_remove_block_tag(s : String, tag : String) -> String {
  let open_pat = "<" + tag
  let close_pat = "</" + tag + ">"
  let mut current = s
  let mut searching = true
  while searching {
    let start = net_index_of_from(current, open_pat, 0)
    if start < 0 {
      searching = false
      continue
    }
    let open_end = net_index_of_from(current, ">", start)
    if open_end < 0 {
      searching = false
      continue
    }
    let close = net_index_of_from(current, close_pat, open_end + 1)
    if close < 0 {
      searching = false
      continue
    }
    let before = cmd_substr_slice(current, 0, start)
    let after = cmd_substr_slice(
      current,
      close + close_pat.length(),
      current.length(),
    )
    current = before + after
  }
  current
}

fn net_strip_html_tags(s : String) -> String {
  let out = StringBuilder::new()
  let mut in_tag = false
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if in_tag {
      if ch == '>' {
        in_tag = false
      }
      continue
    }
    if ch == '<' {
      in_tag = true
      continue
    }
    out.write_char(ch)
  }
  out.to_string()
}

fn net_extract_href(open_tag : String) -> String {
  let lower = net_ascii_lower(open_tag)
  let href_pos = net_index_of_from(lower, "href=", 0)
  if href_pos < 0 {
    return ""
  }
  let value_start = href_pos + 5
  if value_start >= open_tag.length() {
    return ""
  }
  let first = open_tag[value_start].to_int().unsafe_to_char()
  if first == '"' || first == '\'' {
    let end = net_index_of_char(open_tag, first, value_start + 1)
    if end < 0 {
      return ""
    }
    return cmd_substr_slice(open_tag, value_start + 1, end)
  }
  let mut end = value_start
  while end < open_tag.length() {
    let ch = open_tag[end].to_int().unsafe_to_char()
    if net_is_whitespace(ch) || ch == '>' {
      break
    }
    end += 1
  }
  cmd_substr_slice(open_tag, value_start, end)
}

fn net_convert_links(s : String) -> String {
  let out = StringBuilder::new()
  let mut cursor = 0
  while cursor < s.length() {
    let start = net_index_of_from(s, "<a", cursor)
    if start < 0 {
      out.write_string(cmd_substr_slice(s, cursor, s.length()))
      break
    }
    out.write_string(cmd_substr_slice(s, cursor, start))
    let open_end = net_index_of_from(s, ">", start)
    if open_end < 0 {
      out.write_string(cmd_substr_slice(s, start, s.length()))
      break
    }
    let close = net_index_of_from(s, "</a>", open_end + 1)
    if close < 0 {
      out.write_string(cmd_substr_slice(s, start, s.length()))
      break
    }
    let open_tag = cmd_substr_slice(s, start, open_end + 1)
    let href = net_extract_href(open_tag)
    let label_html = cmd_substr_slice(s, open_end + 1, close)
    let label_text = net_trim(net_decode_html_entities(net_strip_html_tags(label_html)))
    if href.length() > 0 {
      out.write_char('[')
      if label_text.length() > 0 {
        out.write_string(label_text)
      } else {
        out.write_string(href)
      }
      out.write_string("](")
      out.write_string(href)
      out.write_char(')')
    } else {
      out.write_string(label_text)
    }
    cursor = close + 4
  }
  out.to_string()
}

fn net_decode_html_entities(s : String) -> String {
  let mut out = s
  out = net_replace_all(out, "&amp;", "&")
  out = net_replace_all(out, "&lt;", "<")
  out = net_replace_all(out, "&gt;", ">")
  out = net_replace_all(out, "&quot;", "\"")
  out = net_replace_all(out, "&#39;", "'")
  out = net_replace_all(out, "&nbsp;", " ")
  out
}

fn net_normalize_markdown(s : String) -> String {
  let trimmed = net_trim(s)
  if trimmed.length() == 0 {
    return ""
  }
  let out = StringBuilder::new()
  let mut newline_run = 0
  for i = 0; i < trimmed.length(); i = i + 1 {
    let ch = trimmed[i].to_int().unsafe_to_char()
    if ch == '\n' {
      newline_run += 1
      if newline_run <= 2 {
        out.write_char('\n')
      }
    } else {
      newline_run = 0
      if ch == '\t' {
        out.write_char(' ')
      } else {
        out.write_char(ch)
      }
    }
  }
  let normalized = out.to_string()
  if normalized.length() == 0 {
    ""
  } else if normalized[normalized.length() - 1].to_int().unsafe_to_char() == '\n' {
    normalized
  } else {
    normalized + "\n"
  }
}

fn net_html_to_markdown(html : String) -> String {
  let mut s = html.replace(old="\r\n", new="\n").replace(old="\r", new="\n")
  s = net_remove_block_tag(s, "script")
  s = net_remove_block_tag(s, "style")
  s = net_convert_links(s)
  s = net_replace_all(s, "<br>", "\n")
  s = net_replace_all(s, "<br/>", "\n")
  s = net_replace_all(s, "<br />", "\n")
  s = net_replace_all(s, "<hr>", "\n---\n")
  s = net_replace_all(s, "<hr/>", "\n---\n")
  s = net_replace_all(s, "<hr />", "\n---\n")
  s = net_replace_all(s, "<h1>", "# ")
  s = net_replace_all(s, "</h1>", "\n\n")
  s = net_replace_all(s, "<h2>", "## ")
  s = net_replace_all(s, "</h2>", "\n\n")
  s = net_replace_all(s, "<h3>", "### ")
  s = net_replace_all(s, "</h3>", "\n\n")
  s = net_replace_all(s, "<h4>", "#### ")
  s = net_replace_all(s, "</h4>", "\n\n")
  s = net_replace_all(s, "<h5>", "##### ")
  s = net_replace_all(s, "</h5>", "\n\n")
  s = net_replace_all(s, "<h6>", "###### ")
  s = net_replace_all(s, "</h6>", "\n\n")
  s = net_replace_all(s, "<p>", "")
  s = net_replace_all(s, "</p>", "\n\n")
  s = net_replace_all(s, "<div>", "")
  s = net_replace_all(s, "</div>", "\n")
  s = net_replace_all(s, "<section>", "")
  s = net_replace_all(s, "</section>", "\n")
  s = net_replace_all(s, "<article>", "")
  s = net_replace_all(s, "</article>", "\n")
  s = net_replace_all(s, "<ul>", "\n")
  s = net_replace_all(s, "</ul>", "\n")
  s = net_replace_all(s, "<ol>", "\n")
  s = net_replace_all(s, "</ol>", "\n")
  s = net_replace_all(s, "<li>", "- ")
  s = net_replace_all(s, "</li>", "\n")
  s = net_replace_all(s, "<pre>", "\n```\n")
  s = net_replace_all(s, "</pre>", "\n```\n")
  s = net_replace_all(s, "<code>", "`")
  s = net_replace_all(s, "</code>", "`")
  s = net_replace_all(s, "<strong>", "**")
  s = net_replace_all(s, "</strong>", "**")
  s = net_replace_all(s, "<b>", "**")
  s = net_replace_all(s, "</b>", "**")
  s = net_replace_all(s, "<em>", "*")
  s = net_replace_all(s, "</em>", "*")
  s = net_replace_all(s, "<i>", "*")
  s = net_replace_all(s, "</i>", "*")
  s = net_strip_html_tags(s)
  s = net_decode_html_entities(s)
  net_normalize_markdown(s)
}

fn net_format_status_line(resp : NetFetchResponse) -> String {
  if resp.status_text.length() > 0 {
    "HTTP/1.1 \{resp.status} \{resp.status_text}\n"
  } else {
    "HTTP/1.1 \{resp.status}\n"
  }
}

fn net_format_headers(resp : NetFetchResponse) -> String {
  let out = StringBuilder::new()
  out.write_string(net_format_status_line(resp))
  for i = 0; i < resp.headers.length(); i = i + 1 {
    let (k, v) = resp.headers[i]
    out.write_string(k)
    out.write_string(": ")
    out.write_string(v)
    out.write_char('\n')
  }
  out.write_char('\n')
  out.to_string()
}

fn net_parse_header(raw : String) -> (String, String)? {
  let idx = net_index_of_char(raw, ':', 0)
  if idx <= 0 {
    return None
  }
  let key = net_trim(cmd_substr_slice(raw, 0, idx))
  let value = net_trim(cmd_substr_slice(raw, idx + 1, raw.length()))
  if key.length() == 0 {
    None
  } else {
    Some((key, value))
  }
}

fn net_curl_error(code : Int, message : String, silent : Bool) -> @ast.ExecResult {
  if silent {
    @ast.ExecResult::new(exit_code=code)
  } else {
    @ast.ExecResult::new(stderr="curl: (\{code}) \{message}\n", exit_code=code)
  }
}

fn cmd_curl(ctx : CommandContext) -> @ast.ExecResult {
  let mut http_method = "GET"
  let mut include_headers = false
  let mut silent = false
  let mut output_path : String? = None
  let mut body : String? = None
  let mut url : String? = None
  let headers : Array[(String, String)] = []

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "--" {
      if i + 1 < ctx.args.length() && url is None {
        url = Some(ctx.args[i + 1])
      }
      break
    } else if arg == "-s" || arg == "--silent" {
      silent = true
      i += 1
    } else if arg == "-i" || arg == "--include" {
      include_headers = true
      i += 1
    } else if arg == "-L" || arg == "--location" {
      i += 1
    } else if arg == "-X" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::new(stderr="curl: option -X requires an argument\n", exit_code=2)
      }
      http_method = net_ascii_upper(ctx.args[i + 1])
      i += 2
    } else if arg.has_prefix("-X") && arg.length() > 2 {
      http_method = net_ascii_upper(cmd_substr_from(arg, 2))
      i += 1
    } else if arg == "-H" || arg == "--header" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::new(stderr="curl: option -H requires an argument\n", exit_code=2)
      }
      match net_parse_header(ctx.args[i + 1]) {
        Some(h) => headers.push(h)
        None => return @ast.ExecResult::new(stderr="curl: invalid header format\n", exit_code=2)
      }
      i += 2
    } else if arg.has_prefix("-H") && arg.length() > 2 {
      match net_parse_header(cmd_substr_from(arg, 2)) {
        Some(h) => headers.push(h)
        None => return @ast.ExecResult::new(stderr="curl: invalid header format\n", exit_code=2)
      }
      i += 1
    } else if arg == "-d" || arg == "--data" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::new(stderr="curl: option -d requires an argument\n", exit_code=2)
      }
      body = Some(ctx.args[i + 1])
      if http_method == "GET" {
        http_method = "POST"
      }
      i += 2
    } else if arg.has_prefix("--data=") {
      body = Some(cmd_substr_from(arg, 7))
      if http_method == "GET" {
        http_method = "POST"
      }
      i += 1
    } else if arg == "-o" || arg == "--output" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::new(stderr="curl: option -o requires an argument\n", exit_code=2)
      }
      output_path = Some(ctx.args[i + 1])
      i += 2
    } else if arg.has_prefix("-o") && arg.length() > 2 {
      output_path = Some(cmd_substr_from(arg, 2))
      i += 1
    } else if arg.length() > 1 && arg[0] == '-' {
      let mut valid_bundle = true
      for j = 1; j < arg.length(); j = j + 1 {
        let flag = arg[j].to_int().unsafe_to_char()
        if flag == 's' {
          silent = true
        } else if flag == 'i' {
          include_headers = true
        } else if flag == 'L' {
          ()
        } else {
          valid_bundle = false
          break
        }
      }
      if not(valid_bundle) {
        return @ast.ExecResult::new(
          stderr="curl: unsupported option -- '\{arg}'\n",
          exit_code=2,
        )
      }
      i += 1
    } else {
      if url is None {
        url = Some(arg)
      }
      i += 1
    }
  }

  let request_url = match url {
    Some(u) => u
    None => return @ast.ExecResult::new(stderr="curl: no URL specified\n", exit_code=2)
  }

  let response = match net_fetch_url(request_url, http_method, headers, body) {
    Ok(resp) => resp
    Err(msg) => return net_curl_error(7, msg, silent)
  }

  let payload = if include_headers {
    net_format_headers(response) + response.body
  } else {
    response.body
  }

  match output_path {
    Some(path) =>
      match net_write_output_file(ctx, "curl", path, payload) {
        Some(err) => @ast.ExecResult::new(stderr=err, exit_code=1)
        None => @ast.ExecResult::new(exit_code=0)
      }
    None => @ast.ExecResult::new(stdout=payload, exit_code=0)
  }
}

fn cmd_html_to_markdown(ctx : CommandContext) -> @ast.ExecResult {
  let mut output_path : String? = None
  let mut source_url : String? = None

  let mut i = 0
  while i < ctx.args.length() {
    let arg = ctx.args[i]
    if arg == "-o" || arg == "--output" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("html-to-markdown: option -o requires an argument\n")
      }
      output_path = Some(ctx.args[i + 1])
      i += 2
    } else if arg == "-u" || arg == "--url" {
      if i + 1 >= ctx.args.length() {
        return @ast.ExecResult::err("html-to-markdown: option --url requires an argument\n")
      }
      source_url = Some(ctx.args[i + 1])
      i += 2
    } else if arg.has_prefix("--url=") {
      source_url = Some(cmd_substr_from(arg, 6))
      i += 1
    } else if arg.length() > 1 && arg[0] == '-' {
      return @ast.ExecResult::err("html-to-markdown: unsupported option -- '\{arg}'\n")
    } else {
      if source_url is None {
        source_url = Some(arg)
      }
      i += 1
    }
  }

  let html_input = match source_url {
    Some(url) =>
      match net_fetch_url(url, "GET", [("accept", "text/html")], None) {
        Ok(resp) => resp.body
        Err(msg) => return @ast.ExecResult::err("html-to-markdown: \{msg}\n")
      }
    None => ctx.stdin_content
  }

  if html_input.length() == 0 {
    return @ast.ExecResult::err("html-to-markdown: missing input\n")
  }

  let markdown = net_html_to_markdown(html_input)
  match output_path {
    Some(path) =>
      match net_write_output_file(ctx, "html-to-markdown", path, markdown) {
        Some(err) => @ast.ExecResult::new(stderr=err, exit_code=1)
        None => @ast.ExecResult::new(exit_code=0)
      }
    None => @ast.ExecResult::new(stdout=markdown, exit_code=0)
  }
}
