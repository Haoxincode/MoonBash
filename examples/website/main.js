import packageInfo from "../../package.json";
import readmeText from "../../docs/README.md";
import architectureText from "../../docs/ARCHITECTURE.md";
import apiText from "../../docs/API.md";
import roadmapText from "../../docs/ROADMAP.md";
import agentsText from "../../AGENTS.md";
import moonMod from "../../src/moon.mod.json";
import { Bash, defineCommand, getCommandNames } from "../../src/wrapper/browser.ts";
import { mount_demo } from "../../src/_build/js/debug/build/website/website.js";

const GITHUB_URL = "https://github.com/Haoxincode/MoonBash";
const DOCS_URL = `${GITHUB_URL}/tree/main/docs`;
const WEBSITE_COMMANDS = ["about", "install", "github"];

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function createAvailabilityStep(name, group = "MoonBash") {
  return {
    kind: "availability",
    group,
    label: name,
    command:
      `command -v ${shellQuote(name)} >/dev/null && ` +
      `printf 'verified %s\\n' ${shellQuote(name)}`,
    expectExitCode: 0,
    expectStdoutIncludes: [`verified ${name}`],
    delayMs: 35,
  };
}

const ABOUT_TEXT = `MoonBash v${packageInfo.version}

Zero-dependency POSIX shell sandbox written in MoonBit and compiled to pure JavaScript.

Highlights
- 87 built-in commands
- In-memory virtual filesystem
- API-compatible with just-bash
- Designed for agents, edge runtimes, and browsers

Try these next
- ls
- tree
- cat README.md | head -20
- grep -n browser ROADMAP.md
- cat package.json | jq .version

GitHub
${GITHUB_URL}
`;

const INSTALL_TEXT = `pnpm add moon-bash

import { Bash } from "moon-bash";

const bash = new Bash({
  env: { USER: "agent" },
});

const result = await bash.exec(
  'echo "Hello from MoonBash!" | tr a-z A-Z'
);

console.log(result.stdout);
`;

const WTF_TEXT = `# MoonBash Browser Demo

This page recreates the justbash.dev experience with MoonBash instead of just-bash.

## What is running here

- A MoonBit package bootstraps the frontend and mounts the terminal shell.
- MoonBash runs entirely in the browser as pure JavaScript.
- The filesystem is virtual and preloaded with docs from this repository.
- No server roundtrip is required for normal shell commands.

## Useful commands

- about
- install
- github
- ls
- tree
- cat README.md | head -30
- grep -n "browser" ROADMAP.md
- cat package.json | jq .version
- sed -n '1,60p' AGENTS.md

## Stack

+----------------------------------------------------+
| Browser                                            |
|  MoonBit frontend -> MoonBash -> InMemory FS       |
|                     |                               |
|                     +-> README / API / ROADMAP     |
+----------------------------------------------------+

The goal is simple: prove MoonBash is usable as a real browser-embedded shell, not just a library API.
`;

const WELCOME_TEXT = String.raw`
 __  __                   ____             __
|  \/  | ___   ___  _ __ | __ )  __ _ ___ / /_
| |\/| |/ _ \ / _ \| '_ \|  _ \ / _\` / __/ __/
| |  | | (_) | (_) | | | | |_) | (_| \__ \ /_
|_|  |_|\___/ \___/|_| |_|____/ \__,_|___/\__|

A browser terminal inspired by justbash.dev, rebuilt for MoonBash.
Runs entirely in memory with docs from this repository preloaded.

Commands: about, install, github, help
Auto-demo: real command verification runs on load
Try later: ls, tree, cat wtf-is-this.md, grep -n browser ROADMAP.md
`;

const VERIFICATION_PLAN = [
  ...getCommandNames().map((name) => createAvailabilityStep(name)),
  ...WEBSITE_COMMANDS.map((name) => createAvailabilityStep(name, "Website")),
  {
    kind: "smoke",
    group: "Smoke",
    label: "filesystem seed",
    command:
      "mkdir -p /tmp/moonbash-demo/docs && " +
      "printf 'alpha\\nbeta\\nalpha\\n' > /tmp/moonbash-demo/docs/data.txt && " +
      "ls /tmp/moonbash-demo/docs",
    expectExitCode: 0,
    expectStdoutIncludes: ["data.txt"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "grep finds beta",
    command: "grep -n beta /tmp/moonbash-demo/docs/data.txt",
    expectExitCode: 0,
    expectStdoutIncludes: ["2:beta"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "sed prints second line",
    command: "sed -n '2p' /tmp/moonbash-demo/docs/data.txt",
    expectExitCode: 0,
    expectStdoutIncludes: ["beta"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "awk counts lines",
    command: "awk 'END { print NR }' /tmp/moonbash-demo/docs/data.txt",
    expectExitCode: 0,
    expectStdoutIncludes: ["3"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "sort and uniq collapse values",
    command: "sort /tmp/moonbash-demo/docs/data.txt | uniq | paste -sd ',' -",
    expectExitCode: 0,
    expectStdoutIncludes: ["alpha,beta"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "find locates demo file",
    command: "find /tmp/moonbash-demo -type f | wc -l",
    expectExitCode: 0,
    expectStdoutIncludes: ["1"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "jq reads package version",
    command: "cat /home/user/package.json | jq -r '.version'",
    expectExitCode: 0,
    expectStdoutIncludes: [packageInfo.version],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "head reads README",
    command: "head -1 /home/user/README.md",
    expectExitCode: 0,
    expectStdoutIncludes: ["# MoonBash"],
    delayMs: 140,
  },
  {
    kind: "smoke",
    group: "Smoke",
    label: "text transform pipeline",
    command: "printf 'moonbash\\n' | tr a-z A-Z | cut -c1-8",
    expectExitCode: 0,
    expectStdoutIncludes: ["MOONBASH"],
    delayMs: 140,
  },
];

globalThis.__moonbash_demo_runtime = {
  Bash,
  defineCommand,
  commandNames: getCommandNames(),
  githubUrl: GITHUB_URL,
  docsUrl: DOCS_URL,
  welcomeText: WELCOME_TEXT,
  initialCommand: "cat wtf-is-this.md",
  aboutText: ABOUT_TEXT,
  installText: INSTALL_TEXT,
  githubText: `${GITHUB_URL}\n`,
  verificationTitle: "Real Browser Verification",
  verificationAutoStart: true,
  verificationInitialDelayMs: 900,
  verificationPlan: VERIFICATION_PLAN,
  cwd: "/home/user",
  env: {
    HOME: "/home/user",
    LANG: "en_US.UTF-8",
    TERM: "xterm-256color",
    USER: "moonbit",
  },
  files: {
    "/home/user/README.md": readmeText,
    "/home/user/ARCHITECTURE.md": architectureText,
    "/home/user/API.md": apiText,
    "/home/user/ROADMAP.md": roadmapText,
    "/home/user/AGENTS.md": agentsText,
    "/home/user/package.json": JSON.stringify(packageInfo, null, 2) + "\n",
    "/home/user/src/moon.mod.json": JSON.stringify(moonMod, null, 2) + "\n",
    "/home/user/wtf-is-this.md": WTF_TEXT,
    "/home/user/links/github.txt": `${GITHUB_URL}\n`,
  },
};

mount_demo();
