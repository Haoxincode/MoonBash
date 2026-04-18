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
  #|     verificationTitle = "Real Browser Verification",
  #|     verificationPlan = [],
  #|     verificationAutoStart = false,
  #|     verificationInitialDelayMs = 900,
  #|     files = {},
  #|     env = {},
  #|     cwd = "/home/user",
  #|   } = runtime;
  #|
  #|   const historyKey = "moonbash-website-history";
  #|   const historyLimit = 100;
  #|   const homeDir = typeof env.HOME === "string" && env.HOME.length > 0 ? env.HOME : "/home/user";
  #|   const availabilityTotal = verificationPlan.filter((step) => step.kind === "availability").length;
  #|   const smokeTotal = verificationPlan.filter((step) => step.kind === "smoke").length;
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
  #|   const createButton = (label, kind = "default") => {
  #|     const button = document.createElement("button");
  #|     button.type = "button";
  #|     button.className = `moonbash-demo-button moonbash-demo-button-${kind}`;
  #|     button.textContent = label;
  #|     return button;
  #|   };
  #|
  #|   const wait = (durationMs) => new Promise((resolve) => {
  #|     window.setTimeout(resolve, durationMs);
  #|   });
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
  #|   const demoPanel = document.createElement("section");
  #|   demoPanel.className = "moonbash-demo";
  #|
  #|   const demoPanelInfo = document.createElement("div");
  #|   demoPanelInfo.className = "moonbash-demo-info";
  #|
  #|   const demoPanelTitleRow = document.createElement("div");
  #|   demoPanelTitleRow.className = "moonbash-demo-title-row";
  #|
  #|   const demoPanelTitle = document.createElement("h2");
  #|   demoPanelTitle.className = "moonbash-demo-title";
  #|   demoPanelTitle.textContent = verificationTitle;
  #|
  #|   const demoPanelState = document.createElement("span");
  #|   demoPanelState.className = "moonbash-demo-state";
  #|
  #|   demoPanelTitleRow.append(demoPanelTitle, demoPanelState);
  #|
  #|   const demoPanelSummary = document.createElement("p");
  #|   demoPanelSummary.className = "moonbash-demo-summary";
  #|
  #|   const demoPanelMeta = document.createElement("div");
  #|   demoPanelMeta.className = "moonbash-demo-meta";
  #|
  #|   const demoPanelProgress = document.createElement("span");
  #|   demoPanelProgress.className = "moonbash-demo-progress";
  #|
  #|   const demoPanelLast = document.createElement("span");
  #|   demoPanelLast.className = "moonbash-demo-last";
  #|
  #|   demoPanelMeta.append(demoPanelProgress, demoPanelLast);
  #|   demoPanelInfo.append(demoPanelTitleRow, demoPanelSummary, demoPanelMeta);
  #|
  #|   const demoPanelActions = document.createElement("div");
  #|   demoPanelActions.className = "moonbash-demo-actions";
  #|
  #|   const demoRunButton = createButton("Run", "primary");
  #|   const demoReplayButton = createButton("Replay", "ghost");
  #|   const demoStopButton = createButton("Stop", "ghost");
  #|
  #|   demoPanelActions.append(demoRunButton, demoReplayButton, demoStopButton);
  #|
  #|   const demoPanelBar = document.createElement("div");
  #|   demoPanelBar.className = "moonbash-demo-bar";
  #|
  #|   const demoPanelBarFill = document.createElement("div");
  #|   demoPanelBarFill.className = "moonbash-demo-bar-fill";
  #|
  #|   demoPanelBar.append(demoPanelBarFill);
  #|   demoPanel.append(demoPanelInfo, demoPanelActions, demoPanelBar);
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
  #|   shell.append(header, demoPanel, viewport);
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
  #|   const createBash = () => new Bash({
  #|     cwd,
  #|     env,
  #|     files,
  #|     customCommands: [aboutCommand, installCommand, githubCommand],
  #|   });
  #|
  #|   const makeShellState = () => ({
  #|     cwd,
  #|     env: { ...env },
  #|   });
  #|
  #|   let bash = createBash();
  #|   let shellState = makeShellState();
  #|   const completionCommands = Array.from(new Set([
  #|     ...commandNames,
  #|     "about",
  #|     "install",
  #|     "github",
  #|     "clear",
  #|     "demo",
  #|     "verify",
  #|   ])).sort();
  #|
  #|   let history = readStoredHistory();
  #|   let historyIndex = history.length;
  #|   let draftCommand = "";
  #|   let commandRunning = false;
  #|   let verificationRunning = false;
  #|   let verificationRunId = 0;
  #|   let verificationCompleted = 0;
  #|   let verificationPassed = 0;
  #|   let verificationFailed = 0;
  #|   let verificationStatus = verificationPlan.length > 0 ? "idle" : "disabled";
  #|   let verificationLastMessage = verificationPlan.length > 0
  #|     ? `${availabilityTotal} registry checks + ${smokeTotal} smoke tests ready.`
  #|     : "No verification plan configured.";
  #|
  #|   const scrollToBottom = () => {
  #|     viewport.scrollTop = viewport.scrollHeight;
  #|   };
  #|
  #|   const syncBusyState = () => {
  #|     const busy = commandRunning || verificationRunning;
  #|     form.classList.toggle("is-busy", busy);
  #|     input.disabled = busy;
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
  #|   const updateVerificationUi = () => {
  #|     const total = verificationPlan.length;
  #|     const progressRatio = total === 0 ? 0 : verificationCompleted / total;
  #|     let stateLabel = "Idle";
  #|     if (verificationStatus === "running") {
  #|       stateLabel = "Running";
  #|     } else if (verificationStatus === "passed") {
  #|       stateLabel = "Passed";
  #|     } else if (verificationStatus === "failed") {
  #|       stateLabel = "Failed";
  #|     } else if (verificationStatus === "stopped") {
  #|       stateLabel = "Stopped";
  #|     } else if (verificationStatus === "disabled") {
  #|       stateLabel = "Disabled";
  #|     }
  #|
  #|     demoPanel.dataset.state = verificationStatus;
  #|     demoPanelState.textContent = stateLabel;
  #|     demoPanelSummary.textContent = total === 0
  #|       ? "No verification plan is configured for this demo."
  #|       : `${availabilityTotal} registry checks + ${smokeTotal} smoke tests. Every step is executed through real MoonBash calls in this browser.`;
  #|     demoPanelProgress.textContent = total === 0
  #|       ? "0 checks"
  #|       : `${verificationCompleted}/${total} checks • ${verificationPassed} passed • ${verificationFailed} failed`;
  #|     demoPanelLast.textContent = verificationLastMessage;
  #|     demoPanelBarFill.style.transform = `scaleX(${progressRatio})`;
  #|     demoRunButton.disabled = verificationRunning || total === 0;
  #|     demoReplayButton.disabled = verificationRunning || total === 0;
  #|     demoStopButton.disabled = !verificationRunning;
  #|   };
  #|
  #|   const updatePrompt = () => {
  #|     location.textContent = collapseHome(shellState.cwd);
  #|     syncBusyState();
  #|     updateVerificationUi();
  #|   };
  #|
  #|   const appendVerificationHint = () => {
  #|     if (verificationPlan.length === 0) {
  #|       return;
  #|     }
  #|     appendBlock(
  #|       `${verificationTitle}\n${availabilityTotal} registry checks + ${smokeTotal} smoke tests are ready. Use the panel above or type demo to run them.`,
  #|       "hint",
  #|     );
  #|   };
  #|
  #|   const resetTerminal = () => {
  #|     output.innerHTML = "";
  #|     if (welcomeText) {
  #|       appendBlock(welcomeText, "intro");
  #|     }
  #|   };
  #|
  #|   const resetShellRuntime = () => {
  #|     bash = createBash();
  #|     shellState = makeShellState();
  #|     historyIndex = history.length;
  #|     draftCommand = "";
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
  #|   const executeShellCommand = async (command, options = {}) => {
  #|     const trimmed = command.trim();
  #|     if (!trimmed || commandRunning) {
  #|       return null;
  #|     }
  #|
  #|     const {
  #|       recordHistory = false,
  #|       focusInput = true,
  #|     } = options;
  #|
  #|     appendCommand(trimmed);
  #|
  #|     if (recordHistory) {
  #|       history.push(trimmed);
  #|       history = history.slice(-historyLimit);
  #|       historyIndex = history.length;
  #|       persistHistory(history);
  #|     }
  #|
  #|     if (trimmed === "clear") {
  #|       resetTerminal();
  #|       appendVerificationHint();
  #|       updatePrompt();
  #|       scrollToBottom();
  #|       return {
  #|         stdout: "",
  #|         stderr: "",
  #|         exitCode: 0,
  #|       };
  #|     }
  #|
  #|     commandRunning = true;
  #|     updatePrompt();
  #|
  #|     try {
  #|       const result = await bash.exec(trimmed, {
  #|         cwd: shellState.cwd,
  #|         env: shellState.env,
  #|       });
  #|
  #|       const normalizedResult = {
  #|         stdout: stripAnsi(result.stdout || ""),
  #|         stderr: stripAnsi(result.stderr || ""),
  #|         exitCode: Number.isFinite(result.exitCode) ? result.exitCode : 1,
  #|       };
  #|
  #|       if (result.env && typeof result.env === "object") {
  #|         shellState.env = { ...result.env };
  #|         if (typeof shellState.env.PWD === "string" && shellState.env.PWD.length > 0) {
  #|           shellState.cwd = shellState.env.PWD;
  #|         }
  #|       }
  #|
  #|       if (normalizedResult.stdout) {
  #|         appendBlock(normalizedResult.stdout, "stdout");
  #|       }
  #|       if (normalizedResult.stderr) {
  #|         appendBlock(normalizedResult.stderr, "stderr");
  #|       }
  #|       if (!normalizedResult.stdout && !normalizedResult.stderr && normalizedResult.exitCode !== 0) {
  #|         appendBlock(`[exit ${normalizedResult.exitCode}]`, "hint");
  #|       }
  #|
  #|       return normalizedResult;
  #|     } catch (error) {
  #|       const message = error && error.message ? error.message : String(error);
  #|       appendBlock(message, "stderr");
  #|       return {
  #|         stdout: "",
  #|         stderr: message,
  #|         exitCode: 1,
  #|       };
  #|     } finally {
  #|       commandRunning = false;
  #|       updatePrompt();
  #|       if (!verificationRunning && focusInput) {
  #|         input.focus();
  #|       }
  #|       scrollToBottom();
  #|     }
  #|   };
  #|
  #|   const evaluateVerificationStep = (step, result) => {
  #|     const diagnostics = [];
  #|     const stdout = result?.stdout ?? "";
  #|     const stderr = result?.stderr ?? "";
  #|
  #|     if (typeof step.expectExitCode === "number" && result?.exitCode !== step.expectExitCode) {
  #|       diagnostics.push(`expected exit ${step.expectExitCode}, got ${result?.exitCode ?? "?"}`);
  #|     }
  #|     for (const needle of step.expectStdoutIncludes ?? []) {
  #|       if (!stdout.includes(needle)) {
  #|         diagnostics.push(`stdout missing ${JSON.stringify(needle)}`);
  #|       }
  #|     }
  #|     for (const needle of step.expectStderrIncludes ?? []) {
  #|       if (!stderr.includes(needle)) {
  #|         diagnostics.push(`stderr missing ${JSON.stringify(needle)}`);
  #|       }
  #|     }
  #|
  #|     const ok = diagnostics.length === 0;
  #|     const statusVerb = step.kind === "availability" ? "registered" : "passed";
  #|
  #|     return {
  #|       ok,
  #|       message: ok
  #|         ? `✓ [${step.group || "Check"}] ${step.label} ${statusVerb}`
  #|         : `✗ [${step.group || "Check"}] ${step.label} — ${diagnostics.join("; ")}`,
  #|     };
  #|   };
  #|
  #|   const stopVerification = (reason = "Verification stopped.") => {
  #|     if (!verificationRunning) {
  #|       return;
  #|     }
  #|     verificationRunId += 1;
  #|     verificationRunning = false;
  #|     verificationStatus = "stopped";
  #|     verificationLastMessage = reason;
  #|     appendBlock(reason, "hint");
  #|     updatePrompt();
  #|     input.focus();
  #|   };
  #|
  #|   const startVerification = async () => {
  #|     if (verificationRunning || verificationPlan.length === 0) {
  #|       return;
  #|     }
  #|
  #|     verificationRunId += 1;
  #|     const runId = verificationRunId;
  #|     verificationRunning = true;
  #|     verificationStatus = "running";
  #|     verificationCompleted = 0;
  #|     verificationPassed = 0;
  #|     verificationFailed = 0;
  #|     verificationLastMessage = `Starting ${verificationPlan.length} real checks...`;
  #|
  #|     resetShellRuntime();
  #|     resetTerminal();
  #|     appendBlock(
  #|       `${verificationTitle}\n${availabilityTotal} registry checks + ${smokeTotal} smoke tests.\nEverything below is executed through real MoonBash calls in this browser.`,
  #|       "hint",
  #|     );
  #|     input.value = "";
  #|     updatePrompt();
  #|     scrollToBottom();
  #|
  #|     for (let index = 0; index < verificationPlan.length; index += 1) {
  #|       if (runId !== verificationRunId) {
  #|         return;
  #|       }
  #|
  #|       const step = verificationPlan[index];
  #|       const delayMs = Number.isFinite(step.delayMs) ? Math.max(0, step.delayMs) : 70;
  #|       if (delayMs > 0) {
  #|         await wait(delayMs);
  #|       }
  #|
  #|       if (runId !== verificationRunId) {
  #|         return;
  #|       }
  #|
  #|       const result = await executeShellCommand(step.command, {
  #|         recordHistory: false,
  #|         focusInput: false,
  #|       });
  #|
  #|       if (runId !== verificationRunId) {
  #|         return;
  #|       }
  #|
  #|       const evaluation = evaluateVerificationStep(step, result);
  #|       verificationCompleted = index + 1;
  #|       if (evaluation.ok) {
  #|         verificationPassed += 1;
  #|       } else {
  #|         verificationFailed += 1;
  #|       }
  #|       verificationLastMessage = evaluation.message;
  #|       appendBlock(evaluation.message, evaluation.ok ? "success" : "stderr");
  #|       updatePrompt();
  #|     }
  #|
  #|     if (runId !== verificationRunId) {
  #|       return;
  #|     }
  #|
  #|     verificationRunning = false;
  #|     verificationStatus = verificationFailed > 0 ? "failed" : "passed";
  #|     verificationLastMessage = verificationFailed > 0
  #|       ? `Completed with ${verificationFailed} failures out of ${verificationPlan.length} checks.`
  #|       : `Completed ${verificationPlan.length} real checks with no failures.`;
  #|     appendBlock(verificationLastMessage, verificationFailed > 0 ? "stderr" : "success");
  #|     updatePrompt();
  #|     input.focus();
  #|   };
  #|
  #|   const runCommand = async (command) => {
  #|     const trimmed = command.trim();
  #|     if (!trimmed || commandRunning || verificationRunning) {
  #|       return;
  #|     }
  #|
  #|     if (trimmed === "demo" || trimmed === "verify") {
  #|       void startVerification();
  #|       input.value = "";
  #|       return;
  #|     }
  #|
  #|     if (trimmed === "demo stop" || trimmed === "verify stop") {
  #|       stopVerification("Verification stopped from terminal command.");
  #|       input.value = "";
  #|       return;
  #|     }
  #|
  #|     await executeShellCommand(trimmed, {
  #|       recordHistory: true,
  #|       focusInput: true,
  #|     });
  #|
  #|     input.value = "";
  #|     draftCommand = "";
  #|     historyIndex = history.length;
  #|     updatePrompt();
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
  #|       appendVerificationHint();
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
  #|   demoRunButton.addEventListener("click", () => {
  #|     void startVerification();
  #|   });
  #|
  #|   demoReplayButton.addEventListener("click", () => {
  #|     void startVerification();
  #|   });
  #|
  #|   demoStopButton.addEventListener("click", () => {
  #|     stopVerification("Verification stopped from controls.");
  #|   });
  #|
  #|   shell.addEventListener("pointerdown", () => {
  #|     if (!commandRunning && !verificationRunning) {
  #|       input.focus();
  #|     }
  #|   });
  #|
  #|   const params = new URLSearchParams(window.location.search);
  #|   const shouldAutoStart = verificationAutoStart &&
  #|     verificationPlan.length > 0 &&
  #|     params.get("autodemo") !== "0";
  #|
  #|   resetTerminal();
  #|   if (!shouldAutoStart) {
  #|     appendVerificationHint();
  #|     input.value = initialCommand;
  #|   } else {
  #|     input.value = "";
  #|   }
  #|   updatePrompt();
  #|
  #|   requestAnimationFrame(() => {
  #|     input.focus();
  #|     const cursor = input.value.length;
  #|     input.setSelectionRange(cursor, cursor);
  #|     scrollToBottom();
  #|   });
  #|
  #|   if (shouldAutoStart) {
  #|     window.setTimeout(() => {
  #|       void startVerification();
  #|     }, verificationInitialDelayMs);
  #|   }
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
