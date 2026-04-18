///|
priv struct ShellState {
  bash : BashRuntime
  mut cwd : String
  mut env : Map[String, String]
}

///|
priv struct AppState {
  config : WebsiteConfig
  dom : DomRefs
  verification_plan : Array[VerificationStep]
  mut shell : ShellState
  mut history : Array[String]
  mut history_index : Int
  mut draft_command : String
  mut command_running : Bool
  mut verification_running : Bool
  mut verification_run_id : Int
  mut verification_completed : Int
  mut verification_passed : Int
  mut verification_failed : Int
  mut verification_status : String
  mut verification_last_message : String
}

///|
fn availability_total(plan : Array[VerificationStep]) -> Int {
  let mut count = 0
  for step in plan {
    if step.kind == "availability" {
      count += 1
    }
  }
  count
}

///|
fn smoke_total(plan : Array[VerificationStep]) -> Int {
  let mut count = 0
  for step in plan {
    if step.kind == "smoke" {
      count += 1
    }
  }
  count
}

///|
fn load_history() -> Array[String] {
  let storage = @dom_ffi.window().local_storage()
  match storage.get_item("moonbash-website-history") {
    Some(raw) => try {
      let parsed = @json.parse(raw[:])
      @json.from_json(parsed)
    } catch {
      _ => []
    }
    None => []
  }
}

///|
fn save_history(history : Array[String]) -> Unit {
  let storage = @dom_ffi.window().local_storage()
  let trimmed : Array[String] = []
  let start = if history.length() > 100 { history.length() - 100 } else { 0 }
  for i in start..<history.length() {
    trimmed.push(history[i])
  }
  storage.set_item("moonbash-website-history", stringify_string_array(trimmed))
}

///|
fn create_shell_state(config : WebsiteConfig) -> ShellState {
  {
    bash: create_bash_runtime(get_runtime_config_json()),
    cwd: config.cwd,
    env: config.env,
  }
}

///|
fn make_app_state(config : WebsiteConfig, dom : DomRefs) -> AppState {
  let plan = build_verification_plan(config)
  {
    config,
    dom,
    verification_plan: plan,
    shell: create_shell_state(config),
    history: load_history(),
    history_index: load_history().length(),
    draft_command: "",
    command_running: false,
    verification_running: false,
    verification_run_id: 0,
    verification_completed: 0,
    verification_passed: 0,
    verification_failed: 0,
    verification_status: if plan.is_empty() { "disabled" } else { "idle" },
    verification_last_message: if plan.is_empty() {
      "No verification plan configured."
    } else {
      "\{availability_total(plan)} registry checks + \{smoke_total(plan)} smoke tests ready."
    },
  }
}

///|
fn reset_shell_runtime(app : Ref[AppState]) -> Unit {
  app.val.shell = create_shell_state(app.val.config)
}

///|
fn update_ui(app : Ref[AppState]) -> Unit {
  let dom = app.val.dom
  let plan = app.val.verification_plan
  let total = plan.length()
  let status_label = match app.val.verification_status {
    "running" => "Running"
    "passed" => "Passed"
    "failed" => "Failed"
    "stopped" => "Stopped"
    "disabled" => "Disabled"
    _ => "Idle"
  }
  dom.location.set_inner_text(collapse_home(app.val.shell.cwd, app.val.config.cwd))
  dom.demo_panel.set_data_attribute("state", app.val.verification_status)
  dom.demo_state.set_inner_text(status_label)
  if total == 0 {
    dom.demo_summary.set_inner_text("No verification plan is configured for this demo.")
    dom.demo_progress.set_inner_text("0 checks")
    dom.demo_bar_fill.reinterpret_as_node().style().set_property("transform", "scaleX(0)")
  } else {
    let avail = availability_total(plan)
    let smoke = smoke_total(plan)
    dom.demo_summary.set_inner_text(
      "\{avail} registry checks + \{smoke} smoke tests. Every step is executed through real MoonBash calls in this browser.",
    )
    dom.demo_progress.set_inner_text(
      "\{app.val.verification_completed}/\{total} checks • \{app.val.verification_passed} passed • \{app.val.verification_failed} failed",
    )
    let ratio = if total == 0 {
      0.0
    } else {
      app.val.verification_completed.to_double() / total.to_double()
    }
    dom.demo_bar_fill.reinterpret_as_node().style().set_property("transform", "scaleX(\{ratio})")
  }
  dom.demo_last.set_inner_text(app.val.verification_last_message)
  set_input_disabled(dom.input_row, dom.input, app.val.command_running || app.val.verification_running)
  set_button_disabled(dom.run_button, app.val.verification_running || total == 0)
  set_button_disabled(dom.replay_button, app.val.verification_running || total == 0)
  set_button_disabled(dom.stop_button, !app.val.verification_running)
}

///|
fn collapse_home(path : String, home : String) -> String {
  if path == home {
    "~"
  } else if path.has_prefix((home + "/")[:]) {
    "~" + path.view(start_offset=home.length()).to_string()
  } else {
    path
  }
}

///|
fn render_intro(app : Ref[AppState]) -> Unit {
  app.val.dom.output.set_inner_html("")
  if app.val.config.welcome_text != "" {
    append_block(app.val.dom, app.val.config.welcome_text, tone="intro")
  }
}

///|
fn append_verification_hint(app : Ref[AppState]) -> Unit {
  let plan = app.val.verification_plan
  if plan.is_empty() {
    return
  }
  append_block(
    app.val.dom,
    "\{app.val.config.verification_title}\n\{availability_total(plan)} registry checks + \{smoke_total(plan)} smoke tests are ready. Use the panel above or type demo to run them.",
    tone="hint",
  )
}

///|
fn list_current_directory(app : Ref[AppState]) -> Array[String] {
  let entries = parse_dir_entries(app.val.shell.bash.readdir_json(app.val.shell.cwd))
  let names : Array[String] = []
  for entry in entries {
    if entry.type_ == "directory" {
      names.push(entry.name + "/")
    } else {
      names.push(entry.name)
    }
  }
  names
}

///|
fn find_word_boundary(value : String, cursor : Int) -> Int {
  let mut start = cursor
  while start > 0 && value[start - 1].to_int() != ' '.to_int() {
    start -= 1
  }
  start
}

///|
fn apply_completion(app : Ref[AppState]) -> Unit {
  let value = app.val.dom.input.value()
  let cursor = html_input_selection_start(app.val.dom.input)
  let start = find_word_boundary(value, cursor)
  let prefix = value.view(start_offset=start, end_offset=cursor).to_string()
  if prefix == "" {
    return
  }
  let candidates = if value.view(end_offset=start).to_string().trim().to_string() == "" {
    let names : Array[String] = []
    for name in app.val.config.command_names {
      names.push(name)
    }
    names.push("about")
    names.push("install")
    names.push("github")
    names.push("clear")
    names.push("demo")
    names.push("verify")
    names
  } else {
    list_current_directory(app)
  }
  let matches : Array[String] = []
  for candidate in candidates {
    if string_lowercase(candidate).has_prefix(string_lowercase(prefix)[:]) {
      matches.push(candidate)
    }
  }
  if matches.is_empty() {
    return
  }
  if matches.length() == 1 {
    let completion = matches[0]
    let next_value =
      value.view(end_offset=start).to_string() +
      completion +
      value.view(start_offset=cursor).to_string()
    app.val.dom.input.set_value(next_value)
    let next_cursor = start + completion.length()
    html_input_set_selection_range(app.val.dom.input, next_cursor, next_cursor)
    return
  }
  append_block(app.val.dom, matches.join("    "[:]), tone="hint")
}

///|
fn persist_history_entry(app : Ref[AppState], command : String) -> Unit {
  app.val.history.push(command)
  if app.val.history.length() > 100 {
    let trimmed : Array[String] = []
    let start = app.val.history.length() - 100
    for i in start..<app.val.history.length() {
      trimmed.push(app.val.history[i])
    }
    app.val.history = trimmed
  }
  app.val.history_index = app.val.history.length()
  save_history(app.val.history)
}

///|
fn apply_exec_result(app : Ref[AppState], result : ExecResult) -> Unit {
  app.val.shell.env = result.env
  match result.env.get("PWD") {
    Some(pwd) if pwd != "" => app.val.shell.cwd = pwd
    _ => ()
  }
  if result.stdout != "" {
    append_block(app.val.dom, result.stdout, tone="stdout")
  }
  if result.stderr != "" {
    append_block(app.val.dom, result.stderr, tone="stderr")
  }
  if result.stdout == "" && result.stderr == "" && result.exit_code != 0 {
    append_block(app.val.dom, "[exit \{result.exit_code}]", tone="hint")
  }
}

///|
fn spawn_background(task : async () -> Unit) -> Unit {
  ignore(@js_async.Promise::from_async(task))
}

///|
async fn run_shell_command_async(
  app : Ref[AppState],
  command : String,
  record_history~ : Bool = false,
  after_done~ : ((ExecResult) -> Unit)? = None,
) -> Unit {
  let trimmed = command.trim().to_string()
  if trimmed == "" || app.val.command_running {
    return
  }
  append_command(app.val.dom, collapse_home(app.val.shell.cwd, app.val.config.cwd), trimmed)
  if record_history {
    persist_history_entry(app, trimmed)
  }
  if trimmed == "clear" {
    render_intro(app)
    append_verification_hint(app)
    update_ui(app)
    element_scroll_to_bottom(app.val.dom.output)
    return
  }
  app.val.command_running = true
  update_ui(app)
  let env_json = encode_string_map(app.val.shell.env)
  let json_result = try {
    app.val.shell.bash.exec_json(trimmed, app.val.shell.cwd, env_json).wait()
  } catch {
    err => "{\"stdout\":\"\",\"stderr\":\"\{err.to_string()}\",\"exitCode\":1,\"env\":{}}"
  }
  let result = parse_exec_result(json_result)
  apply_exec_result(app, result)
  app.val.command_running = false
  update_ui(app)
  html_input_focus(app.val.dom.input)
  match after_done {
    Some(f) => f(result)
    None => ()
  }
}

///|
fn run_shell_command(
  app : Ref[AppState],
  command : String,
  record_history~ : Bool = false,
  after_done~ : ((ExecResult) -> Unit)? = None,
) -> Unit {
  spawn_background(() => {
    run_shell_command_async(app, command, record_history=record_history, after_done=after_done)
  })
}

///|
fn evaluate_step(step : VerificationStep, result : ExecResult) -> (Bool, String) {
  let diagnostics : Array[String] = []
  match step.expect_exit_code {
    Some(expected) if result.exit_code != expected =>
      diagnostics.push("expected exit \{expected}, got \{result.exit_code}")
    _ => ()
  }
  for needle in step.expect_stdout_includes {
    if !result.stdout.contains(needle[:]) {
      diagnostics.push("stdout missing '\{needle}'")
    }
  }
  for needle in step.expect_stderr_includes {
    if !result.stderr.contains(needle[:]) {
      diagnostics.push("stderr missing '\{needle}'")
    }
  }
  let ok = diagnostics.is_empty()
  let verb = if step.kind == "availability" { "registered" } else { "passed" }
  let joined = diagnostics.join("; "[:])
  let message = if ok {
    "✓ [\{step.group}] \{step.label} \{verb}"
  } else {
    "✗ [\{step.group}] \{step.label} — \{joined}"
  }
  (ok, message)
}

///|
async fn run_verification_async(app : Ref[AppState], run_id : Int) -> Unit {
  for i in 0..<app.val.verification_plan.length() {
    if run_id != app.val.verification_run_id {
      return
    }
    let step = app.val.verification_plan[i]
    let delay_ms = if step.delay_ms < 0 { 0 } else { step.delay_ms }
    if delay_ms > 0 {
      @async.sleep(delay_ms)
    }
    if run_id != app.val.verification_run_id {
      return
    }
    let env_json = encode_string_map(app.val.shell.env)
    append_command(app.val.dom, collapse_home(app.val.shell.cwd, app.val.config.cwd), step.command)
    app.val.command_running = true
    update_ui(app)
    let json_result = try {
      app.val.shell.bash.exec_json(step.command, app.val.shell.cwd, env_json).wait()
    } catch {
      err => "{\"stdout\":\"\",\"stderr\":\"\{err.to_string()}\",\"exitCode\":1,\"env\":{}}"
    }
    let result = parse_exec_result(json_result)
    apply_exec_result(app, result)
    app.val.command_running = false
    let (ok, message) = evaluate_step(step, result)
    app.val.verification_completed = i + 1
    if ok {
      app.val.verification_passed += 1
    } else {
      app.val.verification_failed += 1
    }
    app.val.verification_last_message = message
    append_block(app.val.dom, message, tone=if ok { "success" } else { "stderr" })
    update_ui(app)
  }

  if run_id != app.val.verification_run_id {
    return
  }

  app.val.verification_running = false
  app.val.verification_status = if app.val.verification_failed > 0 { "failed" } else { "passed" }
  app.val.verification_last_message = if app.val.verification_failed > 0 {
    "Completed with \{app.val.verification_failed} failures out of \{app.val.verification_plan.length()} checks."
  } else {
    "Completed \{app.val.verification_plan.length()} real checks with no failures."
  }
  append_block(
    app.val.dom,
    app.val.verification_last_message,
    tone=if app.val.verification_failed > 0 { "stderr" } else { "success" },
  )
  update_ui(app)
}

///|
fn start_verification(app : Ref[AppState]) -> Unit {
  if app.val.verification_running || app.val.verification_plan.is_empty() {
    return
  }
  app.val.verification_run_id += 1
  let run_id = app.val.verification_run_id
  app.val.verification_running = true
  app.val.verification_status = "running"
  app.val.verification_completed = 0
  app.val.verification_passed = 0
  app.val.verification_failed = 0
  app.val.verification_last_message = "Starting \{app.val.verification_plan.length()} real checks..."
  reset_shell_runtime(app)
  render_intro(app)
  append_block(
    app.val.dom,
    "\{app.val.config.verification_title}\n\{availability_total(app.val.verification_plan)} registry checks + \{smoke_total(app.val.verification_plan)} smoke tests.\nEverything below is executed through real MoonBash calls in this browser.",
    tone="hint",
  )
  app.val.dom.input.set_value("")
  update_ui(app)
  spawn_background(() => {
    run_verification_async(app, run_id)
  })
}

///|
fn stop_verification(app : Ref[AppState], reason : String) -> Unit {
  if !app.val.verification_running {
    return
  }
  app.val.verification_run_id += 1
  app.val.verification_running = false
  app.val.verification_status = "stopped"
  app.val.verification_last_message = reason
  append_block(app.val.dom, reason, tone="hint")
  update_ui(app)
}

///|
fn handle_enter(app : Ref[AppState]) -> Unit {
  let command = app.val.dom.input.value()
  let trimmed = command.trim().to_string()
  if trimmed == "" {
    return
  }
  if trimmed == "demo" || trimmed == "verify" {
    app.val.dom.input.set_value("")
    start_verification(app)
    return
  }
  if trimmed == "demo stop" || trimmed == "verify stop" {
    app.val.dom.input.set_value("")
    stop_verification(app, "Verification stopped from terminal command.")
    return
  }
  run_shell_command(app, trimmed, record_history=true)
  app.val.dom.input.set_value("")
  app.val.draft_command = ""
  app.val.history_index = app.val.history.length()
}

///|
fn register_handlers(app : Ref[AppState]) -> Unit {
  app.val.dom.run_button.set_onclick(fn(_event) {
    start_verification(app)
  })
  app.val.dom.replay_button.set_onclick(fn(_event) {
    start_verification(app)
  })
  app.val.dom.stop_button.set_onclick(fn(_event) {
    stop_verification(app, "Verification stopped from controls.")
  })
  app.val.dom.shell.set_onclick(fn(_event) {
    if !app.val.command_running {
      html_input_focus(app.val.dom.input)
    }
  })
  app.val.dom.input.set_onkeydown(Some(fn(event : @dom_ffi.KeyboardEvent) {
    let key = event.key()
    if key == "Tab" {
      event.prevent_default()
      apply_completion(app)
      return
    }
    if key == "ArrowUp" {
      event.prevent_default()
      if app.val.history_index == app.val.history.length() {
        app.val.draft_command = app.val.dom.input.value()
      }
      if app.val.history_index > 0 {
        app.val.history_index -= 1
        let command = app.val.history[app.val.history_index]
        app.val.dom.input.set_value(command)
        let cursor = command.length()
        html_input_set_selection_range(app.val.dom.input, cursor, cursor)
      }
      return
    }
    if key == "ArrowDown" {
      event.prevent_default()
      if app.val.history_index < app.val.history.length() - 1 {
        app.val.history_index += 1
        let command = app.val.history[app.val.history_index]
        app.val.dom.input.set_value(command)
      } else {
        app.val.history_index = app.val.history.length()
        app.val.dom.input.set_value(app.val.draft_command)
      }
      let cursor = app.val.dom.input.value().length()
      html_input_set_selection_range(app.val.dom.input, cursor, cursor)
      return
    }
    if key == "Enter" {
      event.prevent_default()
      handle_enter(app)
      return
    }
  }))
}
