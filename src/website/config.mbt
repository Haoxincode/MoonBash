///|
priv struct VerificationStep {
  kind : String
  group : String
  label : String
  command : String
  expect_exit_code : Int?
  expect_stdout_includes : Array[String]
  expect_stderr_includes : Array[String]
  delay_ms : Int
}

///|
priv struct WebsiteConfig {
  version : String
  github_url : String
  docs_url : String
  welcome_text : String
  initial_command : String
  verification_title : String
  verification_auto_start : Bool
  verification_initial_delay_ms : Int
  command_names : Array[String]
  env : Map[String, String]
  cwd : String
}

///|
priv struct ExecResult {
  stdout : String
  stderr : String
  exit_code : Int
  env : Map[String, String]
}

///|
priv struct DirEntry {
  name : String
  type_ : String
}

///|
fn[T : FromJson] decode_json_or(value : Json?, default : T) -> T {
  match value {
    Some(json) => try {
      @json.from_json(json)
    } catch {
      _ => default
    }
    None => default
  }
}

///|
fn json_object_or_empty(json : Json) -> Map[String, Json] {
  match json {
    Json::Object(obj) => obj
    _ => {}
  }
}

///|
fn parse_exec_result(json_text : String) -> ExecResult {
  let parsed = try {
    @json.parse(json_text[:])
  } catch {
    _ => Json::object({})
  }
  let obj = json_object_or_empty(parsed)
  {
    stdout: decode_json_or(obj.get("stdout"), ""),
    stderr: decode_json_or(obj.get("stderr"), ""),
    exit_code: decode_json_or(obj.get("exitCode"), 1),
    env: decode_json_or(obj.get("env"), {}),
  }
}

///|
fn parse_dir_entries(json_text : String) -> Array[DirEntry] {
  let parsed = try {
    @json.parse(json_text[:])
  } catch {
    _ => Json::array([])
  }
  let items : Array[Json] = decode_json_or(Some(parsed), [])
  let entries : Array[DirEntry] = []
  for item in items {
    let obj = json_object_or_empty(item)
    entries.push({
      name: decode_json_or(obj.get("name"), ""),
      type_: decode_json_or(obj.get("type"), ""),
    })
  }
  entries
}

///|
fn parse_website_config(json_text : String) -> WebsiteConfig {
  let parsed = try {
    @json.parse(json_text[:])
  } catch {
    _ => Json::object({})
  }
  let obj = json_object_or_empty(parsed)
  {
    version: decode_json_or(obj.get("version"), "0.1.0"),
    github_url: decode_json_or(obj.get("githubUrl"), ""),
    docs_url: decode_json_or(obj.get("docsUrl"), ""),
    welcome_text: decode_json_or(obj.get("welcomeText"), ""),
    initial_command: decode_json_or(obj.get("initialCommand"), ""),
    verification_title: decode_json_or(obj.get("verificationTitle"), "Real Browser Verification"),
    verification_auto_start: decode_json_or(obj.get("verificationAutoStart"), false),
    verification_initial_delay_ms: decode_json_or(obj.get("verificationInitialDelayMs"), 900),
    command_names: decode_json_or(obj.get("commandNames"), []),
    env: decode_json_or(obj.get("env"), {}),
    cwd: decode_json_or(obj.get("cwd"), "/home/user"),
  }
}

///|
fn shell_quote(value : String) -> String {
  "'\{value}'"
}

///|
fn create_availability_step(name : String, group : String) -> VerificationStep {
  {
    kind: "availability",
    group,
    label: name,
    command: "command -v \{shell_quote(name)} >/dev/null && printf 'verified %s\\n' \{shell_quote(name)}",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "verified \{name}" ],
    expect_stderr_includes: [],
    delay_ms: 35,
  }
}

///|
fn build_verification_plan(config : WebsiteConfig) -> Array[VerificationStep] {
  let website_commands = [ "about", "install", "github" ]
  let steps : Array[VerificationStep] = []
  for name in config.command_names {
    steps.push(create_availability_step(name, "MoonBash"))
  }
  for name in website_commands {
    steps.push(create_availability_step(name, "Website"))
  }
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "filesystem seed",
    command: "mkdir -p /tmp/moonbash-demo/docs && printf 'alpha\\nbeta\\nalpha\\n' > /tmp/moonbash-demo/docs/data.txt && ls /tmp/moonbash-demo/docs",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "data.txt" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "grep finds beta",
    command: "grep -n beta /tmp/moonbash-demo/docs/data.txt",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "2:beta" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "sed prints second line",
    command: "sed -n '2p' /tmp/moonbash-demo/docs/data.txt",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "beta" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "awk counts lines",
    command: "awk 'END { print NR }' /tmp/moonbash-demo/docs/data.txt",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "3" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "sort and uniq collapse values",
    command: "sort /tmp/moonbash-demo/docs/data.txt | uniq | paste -sd ',' -",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "alpha,beta" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "find locates demo file",
    command: "find /tmp/moonbash-demo -type f | wc -l",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "1" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "jq reads package version",
    command: "cat /home/user/package.json | jq -r '.version'",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ config.version ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "head reads README",
    command: "head -1 /home/user/README.md",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "# MoonBash" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "text transform pipeline",
    command: "printf 'moonbash\\n' | tr a-z A-Z | cut -c1-8",
    expect_exit_code: Some(0),
    expect_stdout_includes: [ "MOONBASH" ],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps
}

///|
fn stringify_string_array(values : Array[String]) -> String {
  let items = values.map(fn(value) { Json::string(value) })
  Json::array(items).stringify()
}

///|
fn encode_string_map(values : Map[String, String]) -> String {
  let payload : Map[String, Json] = {}
  for key, value in values {
    payload[key] = Json::string(value)
  }
  Json::object(payload).stringify()
}
