///|
#cfg(target="js")
extern "js" fn mount_demo_impl() -> Unit =
  #| function() {
  #|   const runtime = globalThis.__moonbash_demo_runtime;
  #|   if (!runtime || typeof runtime.Bash !== "function" || typeof runtime.defineCommand !== "function") {
  #|     throw new Error("moonbash website runtime is not configured");
  #|   }
  #|
  #|   const root = document.getElementById("app");
  #|   if (!root) {
  #|     throw new Error("missing #app mount point");
  #|   }
  #|
  #|   const {
  #|     Bash,
  #|     defineCommand,
  #|     commandNames = [],
  #|     githubUrl = "https://github.com/Haoxincode/MoonBash",
  #|     docsUrl = "https://github.com/Haoxincode/MoonBash/tree/main/docs",
  #|     welcomeText = "",
  #|     initialCommand = "",
  #|     aboutText = "",
  #|     installText = "",
  #|     githubText = "",
  #|     files = {},
  #|     env = {},
  #|     cwd = "/home/user",
  #|   } = runtime;
  #|
  #|   const historyKey = "moonbash-website-history";
  #|   const historyLimit = 100;
  #|   const homeDir = typeof env.HOME === "string" && env.HOME.length > 0 ? env.HOME : "/home/user";
  #|
  #|   const readStoredHistory = () => {
  #|     try {
  #|       const raw = sessionStorage.getItem(historyKey);
  #|       if (!raw) {
  #|         return [];
  #|       }
  #|       const parsed = JSON.parse(raw);
  #|       return Array.isArray(parsed) ? parsed.filter((item) => typeof item === "string") : [];
  #|     } catch (_error) {
  #|       return [];
  #|     }
  #|   };
  #|
  #|   const persistHistory = (history) => {
  #|     try {
  #|       sessionStorage.setItem(historyKey, JSON.stringify(history.slice(-historyLimit)));
  #|     } catch (_error) {
  #|       // Ignore storage failures (private mode / disabled storage).
  #|     }
  #|   };
  #|
  #|   const stripAnsi = (value) => {
  #|     if (typeof value !== "string" || value.length === 0) {
  #|       return "";
  #|     }
  #|     return value
  #|       .replace(/\u001b\][^\u0007]*\u0007/g, "")
  #|       .replace(/\u001b\[[0-9;?]*[ -/]*[@-~]/g, "")
  #|       .replace(/\r\n/g, "\n")
  #|       .replace(/\r/g, "\n");
  #|   };
  #|
  #|   const collapseHome = (path) => {
  #|     if (path === homeDir) {
  #|       return "~";
  #|     }
  #|     if (typeof path === "string" && path.startsWith(homeDir + "/")) {
  #|       return "~" + path.slice(homeDir.length);
  #|     }
  #|     return path;
  #|   };
  #|
  #|   const createLink = (label, href) => {
  #|     const link = document.createElement("a");
  #|     link.className = "moonbash-link";
  #|     link.href = href;
  #|     link.target = "_blank";
  #|     link.rel = "noreferrer";
  #|     link.textContent = label;
  #|     return link;
  #|   };
  #|
  #|   root.innerHTML = "";
  #|
  #|   const shell = document.createElement("main");
  #|   shell.className = "moonbash-shell";
  #|
  #|   const header = document.createElement("header");
  #|   header.className = "moonbash-header";
  #|
  #|   const titleWrap = document.createElement("div");
  #|   titleWrap.className = "moonbash-title";
  #|
  #|   const badge = document.createElement("span");
  #|   badge.className = "moonbash-badge";
  #|   badge.textContent = "MoonBit Frontend";
  #|
  #|   const heading = document.createElement("h1");
  #|   heading.className = "moonbash-heading";
  #|   heading.textContent = "moonbash";
  #|
  #|   const subtitle = document.createElement("p");
  #|   subtitle.className = "moonbash-subtitle";
  #|   subtitle.textContent = "A browser terminal recreating justbash.dev with MoonBash running fully in memory.";
  #|
  #|   titleWrap.append(badge, heading, subtitle);
  #|
  #|   const headerMeta = document.createElement("div");
  #|   headerMeta.className = "moonbash-meta";
  #|
  #|   const status = document.createElement("span");
  #|   status.className = "moonbash-status";
  #|   status.textContent = "MoonBit -> JS • Browser Runtime • In-memory FS";
  #|
  #|   const links = document.createElement("nav");
  #|   links.className = "moonbash-nav";
  #|   links.append(createLink("GitHub", githubUrl), createLink("Docs", docsUrl));
  #|
  #|   headerMeta.append(status, links);
  #|   header.append(titleWrap, headerMeta);
  #|
  #|   const viewport = document.createElement("section");
  #|   viewport.className = "moonbash-viewport";
  #|
  #|   const output = document.createElement("div");
  #|   output.className = "moonbash-output";
  #|   output.setAttribute("role", "log");
  #|   output.setAttribute("aria-live", "polite");
  #|
  #|   const form = document.createElement("form");
  #|   form.className = "moonbash-input-row";
  #|   form.setAttribute("autocomplete", "off");
  #|
  #|   const location = document.createElement("span");
  #|   location.className = "moonbash-location";
  #|
  #|   const prompt = document.createElement("span");
  #|   prompt.className = "moonbash-prompt";
  #|   prompt.textContent = "$";
  #|
  #|   const input = document.createElement("input");
  #|   input.className = "moonbash-input";
  #|   input.type = "text";
  #|   input.autocomplete = "off";
  #|   input.autocapitalize = "off";
  #|   input.autocorrect = "off";
  #|   input.spellcheck = false;
  #|   input.setAttribute("aria-label", "MoonBash command input");
  #|
  #|   form.append(location, prompt, input);
  #|   viewport.append(output, form);
  #|   shell.append(header, viewport);
  #|   root.append(shell);
  #|
  #|   const aboutCommand = defineCommand("about", async () => ({
  #|     stdout: aboutText,
  #|     stderr: "",
  #|     exitCode: 0,
  #|   }));
  #|   const installCommand = defineCommand("install", async () => ({
  #|     stdout: installText,
  #|     stderr: "",
  #|     exitCode: 0,
  #|   }));
  #|   const githubCommand = defineCommand("github", async () => ({
  #|     stdout: githubText,
  #|     stderr: "",
  #|     exitCode: 0,
  #|   }));
  #|
  #|   const bash = new Bash({
  #|     cwd,
  #|     env,
  #|     files,
  #|     customCommands: [aboutCommand, installCommand, githubCommand],
  #|   });
  #|
  #|   const completionCommands = Array.from(new Set([
  #|     ...commandNames,
  #|     "about",
  #|     "install",
  #|     "github",
  #|     "clear",
  #|   ])).sort();
  #|
  #|   let shellState = {
  #|     cwd,
  #|     env: { ...env },
  #|   };
  #|   let history = readStoredHistory();
  #|   let historyIndex = history.length;
  #|   let draftCommand = "";
  #|   let running = false;
  #|
  #|   const scrollToBottom = () => {
  #|     viewport.scrollTop = viewport.scrollHeight;
  #|   };
  #|
  #|   const appendBlock = (text, tone = "stdout") => {
  #|     const normalized = stripAnsi(text);
  #|     if (!normalized) {
  #|       return;
  #|     }
  #|     const pre = document.createElement("pre");
  #|     pre.className = `moonbash-line moonbash-line-${tone}`;
  #|     pre.textContent = normalized.replace(/\n+$/, "");
  #|     output.append(pre);
  #|     scrollToBottom();
  #|   };
  #|
  #|   const appendCommand = (command) => {
  #|     const line = document.createElement("div");
  #|     line.className = "moonbash-command";
  #|
  #|     const cwdText = document.createElement("span");
  #|     cwdText.className = "moonbash-command-cwd";
  #|     cwdText.textContent = collapseHome(shellState.cwd);
  #|
  #|     const promptText = document.createElement("span");
  #|     promptText.className = "moonbash-command-prompt";
  #|     promptText.textContent = "$";
  #|
  #|     const commandText = document.createElement("span");
  #|     commandText.className = "moonbash-command-text";
  #|     commandText.textContent = command;
  #|
  #|     line.append(cwdText, promptText, commandText);
  #|     output.append(line);
  #|     scrollToBottom();
  #|   };
  #|
  #|   const updatePrompt = () => {
  #|     location.textContent = collapseHome(shellState.cwd);
  #|     form.classList.toggle("is-busy", running);
  #|   };
  #|
  #|   const resetTerminal = () => {
  #|     output.innerHTML = "";
  #|     if (welcomeText) {
  #|       appendBlock(welcomeText, "intro");
  #|     }
  #|   };
  #|
  #|   const listCurrentDirectory = () => {
  #|     try {
  #|       return bash.getFs()
  #|         .readdir(shellState.cwd)
  #|         .map((entry) => entry.type === "directory" ? `${entry.name}/` : entry.name);
  #|     } catch (_error) {
  #|       return [];
  #|     }
  #|   };
  #|
  #|   const findWordBoundary = (value, cursor) => {
  #|     let start = cursor;
  #|     while (start > 0 && value[start - 1] !== " ") {
  #|       start -= 1;
  #|     }
  #|     return start;
  #|   };
  #|
  #|   const applyCompletion = () => {
  #|     const cursor = input.selectionStart ?? input.value.length;
  #|     const start = findWordBoundary(input.value, cursor);
  #|     const prefix = input.value.slice(start, cursor);
  #|     if (!prefix) {
  #|       return;
  #|     }
  #|     const completingCommand = input.value.slice(0, start).trim().length === 0;
  #|     const candidates = completingCommand ? completionCommands : listCurrentDirectory();
  #|     const matches = candidates.filter((candidate) => candidate.toLowerCase().startsWith(prefix.toLowerCase()));
  #|     if (matches.length === 0) {
  #|       return;
  #|     }
  #|     if (matches.length === 1) {
  #|       const completion = matches[0];
  #|       input.value = input.value.slice(0, start) + completion + input.value.slice(cursor);
  #|       const nextCursor = start + completion.length;
  #|       input.setSelectionRange(nextCursor, nextCursor);
  #|       return;
  #|     }
  #|     let commonPrefix = matches[0];
  #|     for (const match of matches.slice(1)) {
  #|       let index = 0;
  #|       while (
  #|         index < commonPrefix.length &&
  #|         index < match.length &&
  #|         commonPrefix[index].toLowerCase() === match[index].toLowerCase()
  #|       ) {
  #|         index += 1;
  #|       }
  #|       commonPrefix = commonPrefix.slice(0, index);
  #|     }
  #|     if (commonPrefix.length > prefix.length) {
  #|       input.value = input.value.slice(0, start) + commonPrefix + input.value.slice(cursor);
  #|       const nextCursor = start + commonPrefix.length;
  #|       input.setSelectionRange(nextCursor, nextCursor);
  #|       return;
  #|     }
  #|     appendBlock(matches.join("    "), "hint");
  #|   };
  #|
  #|   const runCommand = async (command) => {
  #|     const trimmed = command.trim();
  #|     if (!trimmed || running) {
  #|       return;
  #|     }
  #|
  #|     appendCommand(trimmed);
  #|
  #|     history.push(trimmed);
  #|     history = history.slice(-historyLimit);
  #|     historyIndex = history.length;
  #|     persistHistory(history);
  #|
  #|     if (trimmed === "clear") {
  #|       resetTerminal();
  #|       updatePrompt();
  #|       scrollToBottom();
  #|       return;
  #|     }
  #|
  #|     running = true;
  #|     updatePrompt();
  #|     input.disabled = true;
  #|
  #|     try {
  #|       const result = await bash.exec(trimmed, {
  #|         cwd: shellState.cwd,
  #|         env: shellState.env,
  #|       });
  #|       if (result.env && typeof result.env === "object") {
  #|         shellState.env = { ...result.env };
  #|         if (typeof shellState.env.PWD === "string" && shellState.env.PWD.length > 0) {
  #|           shellState.cwd = shellState.env.PWD;
  #|         }
  #|       }
  #|       if (result.stdout) {
  #|         appendBlock(result.stdout, "stdout");
  #|       }
  #|       if (result.stderr) {
  #|         appendBlock(result.stderr, "stderr");
  #|       }
  #|       if (!result.stdout && !result.stderr && result.exitCode !== 0) {
  #|         appendBlock(`[exit ${result.exitCode}]`, "hint");
  #|       }
  #|     } catch (error) {
  #|       const message = error && error.message ? error.message : String(error);
  #|       appendBlock(message, "stderr");
  #|     } finally {
  #|       running = false;
  #|       input.disabled = false;
  #|       input.value = "";
  #|       input.focus();
  #|       updatePrompt();
  #|       scrollToBottom();
  #|     }
  #|   };
  #|
  #|   form.addEventListener("submit", (event) => {
  #|     event.preventDefault();
  #|     const command = input.value;
  #|     void runCommand(command);
  #|   });
  #|
  #|   input.addEventListener("keydown", (event) => {
  #|     if (event.key === "Tab") {
  #|       event.preventDefault();
  #|       applyCompletion();
  #|       return;
  #|     }
  #|     if (event.key === "ArrowUp") {
  #|       event.preventDefault();
  #|       if (historyIndex === history.length) {
  #|         draftCommand = input.value;
  #|       }
  #|       if (historyIndex > 0) {
  #|         historyIndex -= 1;
  #|         input.value = history[historyIndex];
  #|         const cursor = input.value.length;
  #|         input.setSelectionRange(cursor, cursor);
  #|       }
  #|       return;
  #|     }
  #|     if (event.key === "ArrowDown") {
  #|       event.preventDefault();
  #|       if (historyIndex < history.length - 1) {
  #|         historyIndex += 1;
  #|         input.value = history[historyIndex];
  #|       } else {
  #|         historyIndex = history.length;
  #|         input.value = draftCommand;
  #|       }
  #|       const cursor = input.value.length;
  #|       input.setSelectionRange(cursor, cursor);
  #|       return;
  #|     }
  #|     if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "l") {
  #|       event.preventDefault();
  #|       resetTerminal();
  #|       updatePrompt();
  #|       return;
  #|     }
  #|     if (event.ctrlKey && event.key.toLowerCase() === "c" && input.value.length > 0) {
  #|       event.preventDefault();
  #|       appendCommand(input.value);
  #|       appendBlock("^C", "hint");
  #|       input.value = "";
  #|       historyIndex = history.length;
  #|     }
  #|   });
  #|
  #|   shell.addEventListener("pointerdown", () => {
  #|     if (!running) {
  #|       input.focus();
  #|     }
  #|   });
  #|
  #|   resetTerminal();
  #|   input.value = initialCommand;
  #|   updatePrompt();
  #|   requestAnimationFrame(() => {
  #|     input.focus();
  #|     const cursor = input.value.length;
  #|     input.setSelectionRange(cursor, cursor);
  #|     scrollToBottom();
  #|   });
  #| }

///|
#cfg(not(target="js"))
fn mount_demo_impl() -> Unit {
  ()
}

///|
pub fn mount_demo() -> Unit {
  mount_demo_impl()
}
