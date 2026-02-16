// MoonBash Commands - Custom command bridge
// Executes wrapper-provided custom commands through JS FFI.

priv struct CustomExecResponse {
  handled : Bool
  stdout : String
  stderr : String
  exit_code : Int
  error : String
  has_files : Bool
  files : Array[(String, String)]
}

fn custom_hex_digit(n : Int) -> Char {
  if n < 10 {
    (n + 48).unsafe_to_char()
  } else {
    (n - 10 + 97).unsafe_to_char()
  }
}

fn custom_json_escape_string(s : String) -> String {
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
          out.write_char(custom_hex_digit(code / 16))
          out.write_char(custom_hex_digit(code % 16))
        } else {
          out.write_char(ch)
        }
      }
    }
  }
  out.write_char('"')
  out.to_string()
}

fn custom_args_to_json(args : Array[String]) -> String {
  let out = StringBuilder::new()
  out.write_char('[')
  for i = 0; i < args.length(); i = i + 1 {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string(custom_json_escape_string(args[i]))
  }
  out.write_char(']')
  out.to_string()
}

fn custom_env_to_json(env : Map[String, String]) -> String {
  let keys : Array[String] = []
  for key, _value in env {
    keys.push(key)
  }
  keys.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  let out = StringBuilder::new()
  out.write_char('{')
  for i = 0; i < keys.length(); i = i + 1 {
    if i > 0 {
      out.write_char(',')
    }
    let key = keys[i]
    let value = env.get(key).unwrap_or("")
    out.write_string(custom_json_escape_string(key))
    out.write_char(':')
    out.write_string(custom_json_escape_string(value))
  }
  out.write_char('}')
  out.to_string()
}

fn custom_files_to_json(fs : @fs.InMemoryFs) -> String {
  let keys : Array[String] = []
  for path, entry in fs.entries {
    match entry {
      @fs.FsEntry::File(_) => keys.push(path)
      _ => ()
    }
  }
  keys.sort_by(fn(a, b) {
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
  })
  let out = StringBuilder::new()
  out.write_char('{')
  for i = 0; i < keys.length(); i = i + 1 {
    if i > 0 {
      out.write_char(',')
    }
    let key = keys[i]
    let content = match fs.entries.get(key) {
      Some(@fs.FsEntry::File(data)) => data.content
      _ => ""
    }
    out.write_string(custom_json_escape_string(key))
    out.write_char(':')
    out.write_string(custom_json_escape_string(content))
  }
  out.write_char('}')
  out.to_string()
}

fn custom_build_request_json(
  name : String,
  args : Array[String],
  ctx : CommandContext
) -> String {
  let out = StringBuilder::new()
  out.write_char('{')
  out.write_string("\"name\":")
  out.write_string(custom_json_escape_string(name))
  out.write_string(",\"args\":")
  out.write_string(custom_args_to_json(args))
  out.write_string(",\"stdin\":")
  out.write_string(custom_json_escape_string(ctx.stdin_content))
  out.write_string(",\"cwd\":")
  out.write_string(custom_json_escape_string(ctx.cwd))
  out.write_string(",\"env\":")
  out.write_string(custom_env_to_json(ctx.env))
  out.write_string(",\"files\":")
  out.write_string(custom_files_to_json(ctx.fs))
  out.write_char('}')
  out.to_string()
}

fn custom_parse_int(s : String) -> Int {
  if s.length() == 0 {
    return 0
  }
  let mut sign = 1
  let mut i = 0
  if s[0].to_int().unsafe_to_char() == '-' {
    sign = -1
    i = 1
  } else if s[0].to_int().unsafe_to_char() == '+' {
    i = 1
  }
  let mut value = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch < '0' || ch > '9' {
      break
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    i += 1
  }
  value * sign
}

fn custom_json_get_bool(
  obj : Map[String, Json],
  key : String,
  default_value : Bool
) -> Bool {
  match obj.get(key) {
    Some(Json::True) => true
    Some(Json::False) => false
    Some(Json::Number(n, ..)) => n.to_int() != 0
    Some(Json::String(s)) => s == "1" || s == "true"
    _ => default_value
  }
}

fn custom_json_get_string(
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

fn custom_json_get_int(
  obj : Map[String, Json],
  key : String,
  default_value : Int
) -> Int {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    Some(Json::String(s)) => custom_parse_int(s)
    _ => default_value
  }
}

fn custom_json_get_files(
  obj : Map[String, Json]
) -> (Bool, Array[(String, String)]) {
  match obj.get("files") {
    Some(Json::Object(files_obj)) => {
      let files : Array[(String, String)] = []
      for path, value in files_obj {
        let content = match value {
          Json::String(s) => s
          Json::Number(n, ..) => n.to_int().to_string()
          Json::True => "true"
          Json::False => "false"
          Json::Null => ""
          _ => value.stringify(indent=0)
        }
        files.push((path, content))
      }
      files.sort_by(fn(a, b) {
        if a.0 < b.0 {
          -1
        } else if a.0 > b.0 {
          1
        } else {
          0
        }
      })
      (true, files)
    }
    _ => (false, [])
  }
}

fn custom_parse_response(json_str : String) -> Result[CustomExecResponse, String] {
  let parsed = try {
    @json.parse(json_str[:])
  } catch {
    _ => return Err("custom command bridge returned invalid JSON")
  }
  match parsed {
    Json::Object(obj) => {
      let (has_files, files) = custom_json_get_files(obj)
      Ok({
        handled: custom_json_get_bool(obj, "handled", false),
        stdout: custom_json_get_string(obj, "stdout", ""),
        stderr: custom_json_get_string(obj, "stderr", ""),
        exit_code: custom_json_get_int(
          obj,
          "exitCode",
          custom_json_get_int(obj, "exit_code", 1),
        ),
        error: custom_json_get_string(obj, "error", ""),
        has_files,
        files,
      })
    }
    _ => Err("custom command bridge returned a non-object payload")
  }
}

fn custom_apply_file_updates(
  fs : @fs.InMemoryFs,
  files : Array[(String, String)]
) -> Unit {
  for i = 0; i < files.length(); i = i + 1 {
    let (path, content) = files[i]
    try {
      fs.write_file(path, content)
    } catch {
      _ => ()
    }
  }
}

fn custom_stderr_with_newline(stderr : String) -> String {
  if stderr.length() == 0 {
    return ""
  }
  let last = stderr[stderr.length() - 1].to_int().unsafe_to_char()
  if last == '\n' {
    stderr
  } else {
    stderr + "\n"
  }
}

fn cmd_custom_bridge(ctx : CommandContext) -> @ast.ExecResult {
  if ctx.args.length() == 0 {
    return {
      stdout: "",
      stderr: "__moonbash_custom__: command name argument required\n",
      exit_code: 2,
    }
  }

  let command_name = ctx.args[0]
  let forwarded_args : Array[String] = []
  for i = 1; i < ctx.args.length(); i = i + 1 {
    forwarded_args.push(ctx.args[i])
  }

  let request_json = custom_build_request_json(command_name, forwarded_args, ctx)
  let raw = @ffi.custom_command_sync(request_json)
  let response = match custom_parse_response(raw) {
    Ok(resp) => resp
    Err(msg) => {
      return {
        stdout: "",
        stderr: "__moonbash_custom__: \{msg}\n",
        exit_code: 1,
      }
    }
  }

  if not(response.handled) {
    return {
      stdout: "",
      stderr: "moonbash: \{command_name}: command not found\n",
      exit_code: 127,
    }
  }

  if response.has_files {
    custom_apply_file_updates(ctx.fs, response.files)
  }

  if response.error.length() > 0 {
    let err = StringBuilder::new()
    if response.stderr.length() > 0 {
      err.write_string(custom_stderr_with_newline(response.stderr))
    }
    err.write_string("\{command_name}: \{response.error}\n")
    return {
      stdout: response.stdout,
      stderr: err.to_string(),
      exit_code: if response.exit_code == 0 { 1 } else { response.exit_code },
    }
  }

  {
    stdout: response.stdout,
    stderr: response.stderr,
    exit_code: response.exit_code,
  }
}
