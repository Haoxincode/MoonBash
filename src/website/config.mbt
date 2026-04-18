///|
priv struct DemoStep {
  kind : String
  group : String
  label : String
  text : String
  command : String
  expect_exit_code : Int?
  expect_stdout_includes : Array[String]
  expect_stderr_includes : Array[String]
  delay_ms : Int
}

///|
priv struct DemoMode {
  key : String
  title : String
  summary : String
  intro : String
  autoplay : Bool
  initial_delay_ms : Int
  steps : Array[DemoStep]
}

///|
priv struct WebsiteConfig {
  version : String
  github_url : String
  docs_url : String
  welcome_text : String
  showcase_intro : String
  initial_command : String
  verification_title : String
  showcase_title : String
  default_mode : String
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
    Some(json) => @json.from_json(json) catch { _ => default }
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
  let parsed = @json.parse(json_text[:]) catch { _ => Json::object({}) }
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
  let parsed = @json.parse(json_text[:]) catch { _ => Json::array([]) }
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
  let parsed = @json.parse(json_text[:]) catch { _ => Json::object({}) }
  let obj = json_object_or_empty(parsed)
  {
    version: decode_json_or(obj.get("version"), "0.1.0"),
    github_url: decode_json_or(obj.get("githubUrl"), ""),
    docs_url: decode_json_or(obj.get("docsUrl"), ""),
    welcome_text: decode_json_or(obj.get("welcomeText"), ""),
    showcase_intro: decode_json_or(obj.get("showcaseIntro"), ""),
    initial_command: decode_json_or(obj.get("initialCommand"), ""),
    verification_title: decode_json_or(
      obj.get("verificationTitle"),
      "Real Browser Verification",
    ),
    showcase_title: decode_json_or(
      obj.get("showcaseTitle"),
      "Agent Mission / Browser Ops Console",
    ),
    default_mode: decode_json_or(obj.get("defaultMode"), "verification"),
    verification_auto_start: decode_json_or(
      obj.get("verificationAutoStart"),
      false,
    ),
    verification_initial_delay_ms: decode_json_or(
      obj.get("verificationInitialDelayMs"),
      900,
    ),
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
fn create_availability_step(name : String, group : String) -> DemoStep {
  {
    kind: "availability",
    group,
    label: name,
    text: "",
    command: "command -v \{shell_quote(name)} >/dev/null && printf 'verified %s\\n' \{shell_quote(name)}",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["verified \{name}"],
    expect_stderr_includes: [],
    delay_ms: 35,
  }
}

///|
fn create_banner_step(
  group : String,
  label : String,
  text : String,
) -> DemoStep {
  {
    kind: "banner",
    group,
    label,
    text,
    command: "",
    expect_exit_code: None,
    expect_stdout_includes: [],
    expect_stderr_includes: [],
    delay_ms: 80,
  }
}

///|
fn create_showcase_step(
  group : String,
  label : String,
  command : String,
  expect_stdout_includes : Array[String],
  delay_ms? : Int = 180,
) -> DemoStep {
  {
    kind: "command",
    group,
    label,
    text: "",
    command,
    expect_exit_code: Some(0),
    expect_stdout_includes,
    expect_stderr_includes: [],
    delay_ms,
  }
}

///|
fn build_verification_plan(config : WebsiteConfig) -> Array[DemoStep] {
  let website_commands = ["about", "install", "github"]
  let steps : Array[DemoStep] = []
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
    text: "",
    command: "mkdir -p /tmp/moonbash-demo/docs && printf 'alpha\\nbeta\\nalpha\\n' > /tmp/moonbash-demo/docs/data.txt && ls /tmp/moonbash-demo/docs",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["data.txt"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "grep finds beta",
    text: "",
    command: "grep -n beta /tmp/moonbash-demo/docs/data.txt",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["2:beta"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "sed prints second line",
    text: "",
    command: "sed -n '2p' /tmp/moonbash-demo/docs/data.txt",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["beta"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "awk counts lines",
    text: "",
    command: "awk 'END { print NR }' /tmp/moonbash-demo/docs/data.txt",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["3"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "sort and uniq collapse values",
    text: "",
    command: "sort /tmp/moonbash-demo/docs/data.txt | uniq | paste -sd ',' -",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["alpha,beta"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "find locates demo file",
    text: "",
    command: "find /tmp/moonbash-demo -type f | wc -l",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["1"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "jq reads package version",
    text: "",
    command: "cat /home/user/package.json | jq -r '.version'",
    expect_exit_code: Some(0),
    expect_stdout_includes: [config.version],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "head reads README",
    text: "",
    command: "head -1 /home/user/README.md",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["# MoonBash"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps.push({
    kind: "smoke",
    group: "Smoke",
    label: "text transform pipeline",
    text: "",
    command: "printf 'moonbash\\n' | tr a-z A-Z | cut -c1-8",
    expect_exit_code: Some(0),
    expect_stdout_includes: ["MOONBASH"],
    expect_stderr_includes: [],
    delay_ms: 140,
  })
  steps
}

///|
fn build_showcase_plan() -> Array[DemoStep] {
  [
    create_banner_step(
      "阶段一",
      "核心启动",
      "阶段一：核心启动\n先确认这份中文任务数据已经被真实装载进浏览器内存文件系统。",
    ),
    create_showcase_step(
      "阶段一",
      "数据集巡检",
      "find /demo -maxdepth 2 | sort",
      ["/demo/data", "/demo/logs", "/demo/src", "/demo/notes"],
    ),
    create_banner_step(
      "阶段一",
      "核心启动完成",
      "核心能力已就绪：路径解析、虚拟文件系统和命令分发都在浏览器里真实运行。",
    ),
    create_banner_step(
      "阶段二",
      "文本排障",
      "阶段二：文本排障\n像值班排障一样，用 grep、head、tail 快速定位中文日志里的异常。",
    ),
    create_showcase_step(
      "阶段二",
      "错误聚焦",
      "grep -n ERROR /demo/logs/app.log | head -5",
      ["4:2026-04-18T09:00:04Z ERROR 接口: 上游超时", "6:2026-04-18T09:00:06Z ERROR Worker: 载荷解析失败"],
    ),
    create_showcase_step(
      "阶段二",
      "最近事件窗口",
      "tail -3 /demo/logs/app.log",
      ["ERROR Worker: 载荷解析失败", "INFO Worker: 重试后恢复"],
    ),
    create_banner_step(
      "阶段二",
      "文本排障完成",
      "文本处理链路已验证：日志过滤、截取和输出都是真实命令结果。",
    ),
    create_banner_step(
      "阶段三",
      "数据分析",
      "阶段三：数据分析\n用 jq 和 awk 直接处理中文业务数据，看这套浏览器 shell 能不能真的干活。",
    ),
    create_showcase_step(
      "阶段三",
      "专业版用户数",
      "cat /demo/data/users.json | jq '.users | map(select(.plan==\"专业版\")) | length'",
      ["3"],
    ),
    create_showcase_step(
      "阶段三",
      "营收汇总",
      "awk -F, 'NR>1 { sum += $3 } END { print sum }' /demo/data/revenue.csv",
      ["8270"],
    ),
    create_banner_step(
      "阶段三",
      "数据分析完成",
      "数据工作流已验证：jq 和 awk 处理的是中文数据集，不是伪造输出。",
    ),
    create_banner_step(
      "阶段四",
      "文件系统巡检",
      "阶段四：文件系统巡检\n继续浏览代码快照和说明文档，确认浏览器里的虚拟项目结构可探索。",
    ),
    create_showcase_step(
      "阶段四",
      "源码统计",
      "find /demo/src -name '*.mbt' | wc -l",
      ["5"],
    ),
    create_showcase_step("阶段四", "目录体积", "du /demo/src", [
      "/demo/src",
    ]),
    create_banner_step(
      "阶段四",
      "文件系统巡检完成",
      "文件系统工作流已验证：浏览器 shell 正在遍历、统计并读取真实虚拟文件。",
    ),
    create_banner_step(
      "阶段五",
      "浏览器证明",
      "阶段五：浏览器证明\n最后用一条中文流水线收尾，证明这不是摆设终端，而是可执行的浏览器 shell。",
    ),
    create_showcase_step(
      "阶段五",
      "中文终端流水线",
      "printf '月壤终端浏览器任务流\\n' | cut -c1-10",
      ["月壤终端浏览器任务流"],
    ),
    create_banner_step(
      "阶段五",
      "任务完成",
      "浏览器任务流完成。MoonBash 刚刚在这个标签页里跑完了一整套中文真实工作流。",
    ),
  ]
}

///|
fn build_demo_modes(config : WebsiteConfig) -> Array[DemoMode] {
  [
    {
      key: "verification",
      title: config.verification_title,
      summary: "Registry checks plus smoke tests for command availability and baseline behavior.",
      intro: "",
      autoplay: config.verification_auto_start,
      initial_delay_ms: config.verification_initial_delay_ms,
      steps: build_verification_plan(config),
    },
    {
      key: "showcase",
      title: config.showcase_title,
      summary: "任务式中文工作流演示：日志排障、JSON 分析、CSV 汇总、文件系统巡检，全都在浏览器里真实执行。",
      intro: config.showcase_intro,
      autoplay: false,
      initial_delay_ms: 700,
      steps: build_showcase_plan(),
    },
  ]
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
