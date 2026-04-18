///|
fn mount_demo_impl() -> Unit {
  let config = parse_website_config(get_runtime_config_json())
  let dom = build_dom()
  let app = Ref::new(make_app_state(config, dom))

  dom.title.set_inner_text(config.verification_title)
  dom.github_link.set_attribute("href", config.github_url)
  dom.docs_link.set_attribute("href", config.docs_url)

  register_handlers(app)
  render_intro(app)
  append_mode_hint(app)
  dom.input.set_value(config.initial_command)
  update_ui(app)
  html_input_focus(dom.input)
  element_scroll_to_bottom(dom.output)

  let mode = current_mode(app)
  if mode.autoplay && !mode.steps.is_empty() {
    let delay_ms = if mode.initial_delay_ms < 0 {
      0
    } else {
      mode.initial_delay_ms
    }
    ignore(
      @dom_ffi.set_timeout(
        fn() { start_verification(app) },
        UInt::trunc_double(delay_ms.to_double()),
      ),
    )
  }
}

///|
pub fn mount_demo() -> Unit {
  mount_demo_impl()
}
