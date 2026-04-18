///|
#cfg(target="js")
#external
pub(all) type BashRuntime

///|
#cfg(target="js")
extern "js" fn throw_js_error(message : String) -> Unit =
  #| (message) => { throw new Error(message) }

///|
#cfg(not(target="js"))
fn throw_js_error(_message : String) -> Unit {
  ()
}

///|
#cfg(target="js")
pub extern "js" fn get_runtime_config_json() -> String =
  #| () => globalThis.__moonbash_demo_config_json ?? "{}"

///|
#cfg(not(target="js"))
fn get_runtime_config_json() -> String {
  "{}"
}

///|
#cfg(target="js")
pub extern "js" fn create_bash_runtime(config_json : String) -> BashRuntime =
  #| (configJson) => {
  #|   const libs = globalThis.__moonbash_demo_runtime_libs;
  #|   if (!libs || typeof libs.Bash !== "function" || typeof libs.defineCommand !== "function") {
  #|     throw new Error("moonbash website runtime libraries are not configured");
  #|   }
  #|   const config = JSON.parse(configJson || "{}");
  #|   const Bash = libs.Bash;
  #|   const defineCommand = libs.defineCommand;
  #|   const aboutCmd = defineCommand("about", async () => ({
  #|     stdout: String(config.aboutText ?? ""),
  #|     stderr: "",
  #|     exitCode: 0,
  #|   }));
  #|   const installCmd = defineCommand("install", async () => ({
  #|     stdout: String(config.installText ?? ""),
  #|     stderr: "",
  #|     exitCode: 0,
  #|   }));
  #|   const githubCmd = defineCommand("github", async () => ({
  #|     stdout: String(config.githubText ?? ""),
  #|     stderr: "",
  #|     exitCode: 0,
  #|   }));
  #|   return new Bash({
  #|     cwd: String(config.cwd ?? "/home/user"),
  #|     env: config.env ?? {},
  #|     files: config.files ?? {},
  #|     customCommands: [aboutCmd, installCmd, githubCmd],
  #|   });
  #| }

///|
#cfg(target="js")
pub extern "js" fn BashRuntime::exec_json(
  self : BashRuntime,
  script : String,
  cwd : String,
  env_json : String,
) -> @js_async.Promise[String] =
  #| async (self, script, cwd, envJson) => {
  #|   const env = envJson && envJson.length > 0 ? JSON.parse(envJson) : {};
  #|   try {
  #|     const result = await self.exec(script, { cwd, env });
  #|     return JSON.stringify(result);
  #|   } catch (error) {
  #|     const message = error && error.message ? error.message : String(error);
  #|     return JSON.stringify({
  #|       stdout: "",
  #|       stderr: message,
  #|       exitCode: 1,
  #|       env,
  #|     });
  #|   }
  #| }

///|
#cfg(target="js")
pub extern "js" fn BashRuntime::readdir_json(
  self : BashRuntime,
  path : String,
) -> String =
  #| (self, path) => {
  #|   try {
  #|     return JSON.stringify(self.getFs().readdir(path));
  #|   } catch (_error) {
  #|     return "[]";
  #|   }
  #| }

///|
#cfg(target="js")
pub extern "js" fn element_scroll_to_bottom(element : @dom_ffi.Element) -> Unit =
  #| (element) => {
  #|   element.scrollTop = element.scrollHeight;
  #| }

///|
#cfg(target="js")
pub extern "js" fn html_input_focus(input : @dom_ffi.HtmlInputElement) -> Unit =
  #| (input) => input.focus()

///|
#cfg(target="js")
pub extern "js" fn html_input_set_disabled(
  input : @dom_ffi.HtmlInputElement,
  disabled : Bool,
) -> Unit =
  #| (input, disabled) => { input.disabled = disabled }

///|
#cfg(target="js")
pub extern "js" fn html_input_selection_start(
  input : @dom_ffi.HtmlInputElement,
) -> Int =
  #| (input) => input.selectionStart ?? input.value.length

///|
#cfg(target="js")
pub extern "js" fn html_input_set_selection_range(
  input : @dom_ffi.HtmlInputElement,
  start : Int,
  end_ : Int,
) -> Unit =
  #| (input, start, end) => input.setSelectionRange(start, end)

///|
#cfg(target="js")
pub extern "js" fn string_lowercase(value : String) -> String =
  #| (value) => value.toLowerCase()
