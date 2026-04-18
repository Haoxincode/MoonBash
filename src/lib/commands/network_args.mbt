// moon_bash Commands - Network argument parsing and URL normalization

///|
priv struct NetCurlConfig {
  http_method : String
  include_headers : Bool
  silent : Bool
  output_path : String?
  body : String?
  url : String?
  headers : Array[(String, String)]
}

///|
priv struct NetHtmlToMarkdownConfig {
  output_path : String?
  source_url : String?
}

///|
fn net_arg_char_at(arg : String, idx : Int) -> Char {
  arg[idx].to_int().unsafe_to_char()
}

///|
fn net_arg_starts_with_dash(arg : String) -> Bool {
  arg.length() > 0 && net_arg_char_at(arg, 0) == '-'
}

///|
fn net_args_contain_double_dash(args : Array[String]) -> Bool {
  for arg in args {
    if arg == "--" {
      return true
    }
  }
  false
}

///|
fn net_curl_unsupported_option_result(arg : String) -> @ast.ExecResult {
  @ast.ExecResult::new(
    stderr="curl: unsupported option -- '\{arg}'\n",
    exit_code=2,
  )
}

///|
fn net_html_to_markdown_unsupported_option_result(
  arg : String,
) -> @ast.ExecResult {
  @ast.ExecResult::new(
    stderr="html-to-markdown: unsupported option -- '\{arg}'\n",
    exit_code=1,
  )
}

///|
fn net_curl_has_invalid_short_bundle(arg : String) -> Bool {
  if arg.length() <= 1 || net_arg_char_at(arg, 0) != '-' {
    return false
  }
  if arg.length() >= 2 && net_arg_char_at(arg, 1) == '-' {
    return false
  }
  if arg == "-X" || arg == "-H" || arg == "-d" || arg == "-o" {
    return false
  }
  if arg.length() > 2 {
    let first = net_arg_char_at(arg, 1)
    if first == 'X' || first == 'H' || first == 'o' {
      return false
    }
  }
  for i in 1..<arg.length() {
    let flag = net_arg_char_at(arg, i)
    if flag == 'X' || flag == 'H' || flag == 'd' || flag == 'o' {
      return true
    }
  }
  false
}

///|
fn net_curl_preprocess_args(args : Array[String]) -> Array[String] {
  let normalized : Array[String] = []
  for arg in args {
    if arg.has_prefix("-X") && arg.length() > 2 {
      normalized.push("-X")
      normalized.push(cmd_substr_from(arg, 2))
    } else if arg.has_prefix("-H") && arg.length() > 2 {
      normalized.push("-H")
      normalized.push(cmd_substr_from(arg, 2))
    } else if arg.has_prefix("-o") && arg.length() > 2 {
      normalized.push("-o")
      normalized.push(cmd_substr_from(arg, 2))
    } else {
      normalized.push(arg)
    }
  }
  normalized
}

///|
fn net_curl_parse_error_result(msg : String) -> @ast.ExecResult {
  if msg == "Option --method requires a value" ||
    msg == "Option -X requires a value" {
    return @ast.ExecResult::new(
      stderr="curl: option -X requires an argument\n",
      exit_code=2,
    )
  }
  if msg == "Collection --header requires a value" ||
    msg == "Collection -H requires a value" {
    return @ast.ExecResult::new(
      stderr="curl: option -H requires an argument\n",
      exit_code=2,
    )
  }
  if msg == "Option --data requires a value" ||
    msg == "Option -d requires a value" {
    return @ast.ExecResult::new(
      stderr="curl: option -d requires an argument\n",
      exit_code=2,
    )
  }
  if msg == "Option --output requires a value" ||
    msg == "Option -o requires a value" {
    return @ast.ExecResult::new(
      stderr="curl: option -o requires an argument\n",
      exit_code=2,
    )
  }
  @ast.ExecResult::new(stderr="curl: \{msg}\n", exit_code=2)
}

///|
fn net_html_to_markdown_parse_error_result(msg : String) -> @ast.ExecResult {
  if msg == "Option --output requires a value" ||
    msg == "Option -o requires a value" {
    return @ast.ExecResult::err(
      "html-to-markdown: option -o requires an argument\n",
    )
  }
  if msg == "Option --url requires a value" ||
    msg == "Option -u requires a value" {
    return @ast.ExecResult::err(
      "html-to-markdown: option --url requires an argument\n",
    )
  }
  @ast.ExecResult::err("html-to-markdown: \{msg}\n")
}

///|
fn net_parse_curl_args(
  raw_args : Array[String],
) -> Result[NetCurlConfig, @ast.ExecResult] {
  for arg in raw_args {
    if net_curl_has_invalid_short_bundle(arg) {
      return Err(net_curl_unsupported_option_result(arg))
    }
  }

  let args = net_curl_preprocess_args(raw_args)
  let aliases : Map[String, String] = {
    "s": "silent",
    "i": "include",
    "L": "location",
    "X": "method",
    "H": "header",
    "d": "data",
    "o": "output",
  }
  let parsed = @parse_args.parse(
    args,
    flags=["silent", "include", "location"],
    options=["method", "data", "output"],
    collections=["header"],
    aliases~,
  ) catch {
    @parse_args.ParseError(msg) => return Err(net_curl_parse_error_result(msg))
  }

  if !net_args_contain_double_dash(args) {
    for positional in parsed.positional {
      if positional.length() > 1 && net_arg_starts_with_dash(positional) {
        return Err(net_curl_unsupported_option_result(positional))
      }
    }
  }

  let headers : Array[(String, String)] = []
  match parsed.collections.get("header") {
    Some(raw_headers) =>
      for raw_header in raw_headers {
        match net_parse_header(raw_header) {
          Some(header) => headers.push(header)
          None =>
            return Err(
              @ast.ExecResult::new(
                stderr="curl: invalid header format\n",
                exit_code=2,
              ),
            )
        }
      }
    None => ()
  }

  let mut http_method = parsed.options.get("method").unwrap_or("GET")
  http_method = net_ascii_upper(http_method)
  let body = parsed.options.get("data")
  if body is Some(_) && http_method == "GET" {
    http_method = "POST"
  }

  Ok({
    http_method,
    include_headers: parsed.flags.get("include").unwrap_or(false),
    silent: parsed.flags.get("silent").unwrap_or(false),
    output_path: parsed.options.get("output"),
    body,
    url: if parsed.positional.length() > 0 {
      Some(parsed.positional[0])
    } else {
      None
    },
    headers,
  })
}

///|
fn net_parse_html_to_markdown_args(
  raw_args : Array[String],
) -> Result[NetHtmlToMarkdownConfig, @ast.ExecResult] {
  let aliases : Map[String, String] = { "o": "output", "u": "url" }
  let parsed = @parse_args.parse(raw_args, options=["output", "url"], aliases~) catch {
    @parse_args.ParseError(msg) =>
      return Err(net_html_to_markdown_parse_error_result(msg))
  }

  if !net_args_contain_double_dash(raw_args) {
    for positional in parsed.positional {
      if positional.length() > 1 && net_arg_starts_with_dash(positional) {
        return Err(net_html_to_markdown_unsupported_option_result(positional))
      }
    }
  }

  Ok({
    output_path: parsed.options.get("output"),
    source_url: match parsed.options.get("url") {
      Some(url) => Some(url)
      None =>
        if parsed.positional.length() > 0 {
          Some(parsed.positional[0])
        } else {
          None
        }
    },
  })
}

///|
fn net_normalize_request_url(raw_url : String) -> Result[String, String] {
  match @url.Url::try_parse(raw_url[:]) {
    Some(url) => {
      let protocol = url.protocol()
      if protocol == "http:" || protocol == "https:" {
        Ok(url.href())
      } else {
        Err("unsupported URL scheme")
      }
    }
    None => Err("invalid URL")
  }
}
