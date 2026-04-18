///|
priv struct DomRefs {
  shell : @dom_ffi.Element
  title : @dom_ffi.Element
  github_link : @dom_ffi.Element
  docs_link : @dom_ffi.Element
  output : @dom_ffi.Element
  input_row : @dom_ffi.Element
  input : @dom_ffi.HtmlInputElement
  location : @dom_ffi.Element
  demo_panel : @dom_ffi.Element
  demo_state : @dom_ffi.Element
  demo_summary : @dom_ffi.Element
  demo_progress : @dom_ffi.Element
  demo_last : @dom_ffi.Element
  demo_bar_fill : @dom_ffi.Element
  run_button : @dom_ffi.Element
  replay_button : @dom_ffi.Element
  stop_button : @dom_ffi.Element
}

///|
fn dom_document() -> @dom_ffi.Document {
  @dom_ffi.window().document()
}

///|
fn create_element(
  tag : String,
  class_name~ : String = "",
  text~ : String = "",
) -> @dom_ffi.Element {
  let element = dom_document().create_element(tag)
  if class_name != "" {
    element.set_attribute("class", class_name)
  }
  if text != "" {
    element.set_inner_text(text)
  }
  element
}

///|
fn append(parent : @dom_ffi.Element, child : @dom_ffi.Element) -> Unit {
  parent.append_child(child.reinterpret_as_node())
}

///|
fn set_button_disabled(element : @dom_ffi.Element, disabled : Bool) -> Unit {
  if disabled {
    element.set_attribute("disabled", "disabled")
  } else {
    element.remove_attribute("disabled")
  }
}

///|
fn set_input_disabled(input_row : @dom_ffi.Element, input : @dom_ffi.HtmlInputElement, disabled : Bool) -> Unit {
  if disabled {
    input_row.set_attribute("class", "moonbash-input-row is-busy")
    html_input_set_disabled(input, true)
  } else {
    input_row.set_attribute("class", "moonbash-input-row")
    html_input_set_disabled(input, false)
  }
}

///|
fn append_block(dom : DomRefs, text : String, tone~ : String = "stdout") -> Unit {
  if text == "" {
    return
  }
  let block = create_element("pre", class_name="moonbash-line moonbash-line-\{tone}")
  let normalized = text.trim_end().to_string()
  if normalized == "" {
    block.set_inner_text(text)
  } else {
    block.set_inner_text(normalized)
  }
  append(dom.output, block)
  element_scroll_to_bottom(dom.output)
}

///|
fn append_command(dom : DomRefs, cwd : String, command : String) -> Unit {
  let line = create_element("div", class_name="moonbash-command")
  let cwd_text = create_element("span", class_name="moonbash-command-cwd", text=cwd)
  let prompt = create_element("span", class_name="moonbash-command-prompt", text="$")
  let command_text = create_element("span", class_name="moonbash-command-text", text=command)
  append(line, cwd_text)
  append(line, prompt)
  append(line, command_text)
  append(dom.output, line)
  element_scroll_to_bottom(dom.output)
}

///|
fn build_dom() -> DomRefs {
  let root = match @dom_ffi.document_get_element_by_id("app") {
    Some(element) => element
    None => {
      throw_js_error("missing #app mount point")
      create_element("div")
    }
  }
  root.set_inner_html("")

  let shell = create_element("main", class_name="moonbash-shell")
  append(root, shell)

  let header = create_element("header", class_name="moonbash-header")
  append(shell, header)

  let title_wrap = create_element("div", class_name="moonbash-title")
  let badge = create_element("span", class_name="moonbash-badge", text="MoonBit Frontend")
  let heading = create_element("h1", class_name="moonbash-heading", text="moonbash")
  let subtitle = create_element(
    "p",
    class_name="moonbash-subtitle",
    text="A browser terminal recreating justbash.dev with MoonBash running fully in memory.",
  )
  append(title_wrap, badge)
  append(title_wrap, heading)
  append(title_wrap, subtitle)
  append(header, title_wrap)

  let meta = create_element("div", class_name="moonbash-meta")
  let status = create_element(
    "span",
    class_name="moonbash-status",
    text="MoonBit -> JS • Browser Runtime • In-memory FS",
  )
  let nav = create_element("nav", class_name="moonbash-nav")
  let github = create_element("a", class_name="moonbash-link", text="GitHub")
  github.set_attribute("target", "_blank")
  github.set_attribute("rel", "noreferrer")
  let docs = create_element("a", class_name="moonbash-link", text="Docs")
  docs.set_attribute("target", "_blank")
  docs.set_attribute("rel", "noreferrer")
  append(nav, github)
  append(nav, docs)
  append(meta, status)
  append(meta, nav)
  append(header, meta)

  let demo_panel = create_element("section", class_name="moonbash-demo")
  append(shell, demo_panel)

  let demo_info = create_element("div", class_name="moonbash-demo-info")
  let title_row = create_element("div", class_name="moonbash-demo-title-row")
  let demo_title = create_element("h2", class_name="moonbash-demo-title")
  let demo_state = create_element("span", class_name="moonbash-demo-state")
  append(title_row, demo_title)
  append(title_row, demo_state)
  let demo_summary = create_element("p", class_name="moonbash-demo-summary")
  let demo_meta = create_element("div", class_name="moonbash-demo-meta")
  let demo_progress = create_element("span", class_name="moonbash-demo-progress")
  let demo_last = create_element("span", class_name="moonbash-demo-last")
  append(demo_meta, demo_progress)
  append(demo_meta, demo_last)
  append(demo_info, title_row)
  append(demo_info, demo_summary)
  append(demo_info, demo_meta)

  let demo_actions = create_element("div", class_name="moonbash-demo-actions")
  let run_button = create_element("button", class_name="moonbash-demo-button moonbash-demo-button-primary", text="Run")
  run_button.set_attribute("type", "button")
  let replay_button = create_element("button", class_name="moonbash-demo-button moonbash-demo-button-ghost", text="Replay")
  replay_button.set_attribute("type", "button")
  let stop_button = create_element("button", class_name="moonbash-demo-button moonbash-demo-button-ghost", text="Stop")
  stop_button.set_attribute("type", "button")
  append(demo_actions, run_button)
  append(demo_actions, replay_button)
  append(demo_actions, stop_button)

  let demo_bar = create_element("div", class_name="moonbash-demo-bar")
  let demo_bar_fill = create_element("div", class_name="moonbash-demo-bar-fill")
  append(demo_bar, demo_bar_fill)

  append(demo_panel, demo_info)
  append(demo_panel, demo_actions)
  append(demo_panel, demo_bar)

  let viewport = create_element("section", class_name="moonbash-viewport")
  append(shell, viewport)
  let output = create_element("div", class_name="moonbash-output")
  output.set_attribute("role", "log")
  output.set_attribute("aria-live", "polite")
  append(viewport, output)

  let input_row = create_element("div", class_name="moonbash-input-row")
  let location = create_element("span", class_name="moonbash-location")
  let prompt = create_element("span", class_name="moonbash-prompt", text="$")
  let input_element = create_element("input", class_name="moonbash-input")
  input_element.set_attribute("type", "text")
  input_element.set_attribute("autocomplete", "off")
  input_element.set_attribute("autocapitalize", "off")
  input_element.set_attribute("autocorrect", "off")
  input_element.set_attribute("spellcheck", "false")
  input_element.set_attribute("aria-label", "MoonBash command input")
  append(input_row, location)
  append(input_row, prompt)
  append(input_row, input_element)
  append(viewport, input_row)

  {
    shell,
    title: demo_title,
    github_link: github,
    docs_link: docs,
    output,
    input_row,
    input: input_element.reinterpret_as_html_input_element(),
    location,
    demo_panel,
    demo_state,
    demo_summary,
    demo_progress,
    demo_last,
    demo_bar_fill,
    run_button,
    replay_button,
    stop_button,
  }
}
