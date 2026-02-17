// moon_bash Commands - VM Bridge
// python3, sqlite3

priv struct VmExecResponse {
  stdout : String
  stderr : String
  exit_code : Int
  error : String
  has_files : Bool
  files : Array[(String, String)]
}

fn vm_hex_digit(n : Int) -> Char {
  if n < 10 {
    (n + 48).unsafe_to_char()
  } else {
    (n - 10 + 97).unsafe_to_char()
  }
}

fn vm_json_escape_string(s : String) -> String {
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
          out.write_char(vm_hex_digit(code / 16))
          out.write_char(vm_hex_digit(code % 16))
        } else {
          out.write_char(ch)
        }
      }
    }
  }
  out.write_char('"')
  out.to_string()
}

fn vm_args_to_json(args : Array[String]) -> String {
  let out = StringBuilder::new()
  out.write_char('[')
  for i = 0; i < args.length(); i = i + 1 {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string(vm_json_escape_string(args[i]))
  }
  out.write_char(']')
  out.to_string()
}

fn vm_env_to_json(env : Map[String, String]) -> String {
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
    out.write_string(vm_json_escape_string(key))
    out.write_char(':')
    out.write_string(vm_json_escape_string(value))
  }
  out.write_char('}')
  out.to_string()
}

fn vm_files_to_json(fs : @fs.InMemoryFs) -> String {
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
    out.write_string(vm_json_escape_string(key))
    out.write_char(':')
    out.write_string(vm_json_escape_string(content))
  }
  out.write_char('}')
  out.to_string()
}

fn vm_build_request_json(
  runtime_name : String,
  ctx : CommandContext
) -> String {
  let out = StringBuilder::new()
  out.write_char('{')
  out.write_string("\"runtime\":")
  out.write_string(vm_json_escape_string(runtime_name))
  out.write_string(",\"args\":")
  out.write_string(vm_args_to_json(ctx.args))
  out.write_string(",\"stdin\":")
  out.write_string(vm_json_escape_string(ctx.stdin_content))
  out.write_string(",\"cwd\":")
  out.write_string(vm_json_escape_string(ctx.cwd))
  out.write_string(",\"env\":")
  out.write_string(vm_env_to_json(ctx.env))
  out.write_string(",\"files\":")
  out.write_string(vm_files_to_json(ctx.fs))
  out.write_char('}')
  out.to_string()
}

fn vm_json_get_string(
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

fn vm_json_get_int(
  obj : Map[String, Json],
  key : String,
  default_value : Int
) -> Int {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    Some(Json::String(s)) => cmd_parse_int(s).to_int()
    _ => default_value
  }
}

fn vm_json_get_files(
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

fn vm_apply_file_updates(
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

fn vm_parse_response(json_str : String) -> Result[VmExecResponse, String] {
  let parsed = try {
    @json.parse(json_str[:])
  } catch {
    _ => return Err("vm bridge returned invalid JSON")
  }
  match parsed {
    Json::Object(obj) => {
      let exit_code = vm_json_get_int(
        obj,
        "exitCode",
        vm_json_get_int(obj, "exit_code", 1),
      )
      let (has_files, files) = vm_json_get_files(obj)
      Ok({
        stdout: vm_json_get_string(obj, "stdout", ""),
        stderr: vm_json_get_string(obj, "stderr", ""),
        exit_code,
        error: vm_json_get_string(obj, "error", ""),
        has_files,
        files,
      })
    }
    _ => Err("vm bridge returned a non-object payload")
  }
}

fn vm_stderr_with_newline(stderr : String) -> String {
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

fn vm_run(runtime_name : String, ctx : CommandContext) -> @ast.ExecResult {
  let request_json = vm_build_request_json(runtime_name, ctx)
  let raw = @ffi.vm_sync(request_json)
  let response = match vm_parse_response(raw) {
    Ok(resp) => resp
    Err(msg) => {
      return {
        stdout: "",
        stderr: "\{runtime_name}: \{msg}\n",
        exit_code: 1,
      }
    }
  }
  if response.error.length() > 0 {
    let err = StringBuilder::new()
    if response.stderr.length() > 0 {
      err.write_string(vm_stderr_with_newline(response.stderr))
    }
    err.write_string("\{runtime_name}: \{response.error}\n")
    return {
      stdout: response.stdout,
      stderr: err.to_string(),
      exit_code: if response.exit_code == 0 { 1 } else { response.exit_code },
    }
  }
  if response.has_files {
    vm_apply_file_updates(ctx.fs, response.files)
  }
  {
    stdout: response.stdout,
    stderr: response.stderr,
    exit_code: response.exit_code,
  }
}

fn cmd_python3(ctx : CommandContext) -> @ast.ExecResult {
  vm_run("python3", ctx)
}

fn cmd_sqlite3(ctx : CommandContext) -> @ast.ExecResult {
  vm_run("sqlite3", ctx)
}
