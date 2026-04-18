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

const SHOWCASE_INTRO = String.raw`
启动序列: parser, expander, pipes, VFS, jq, awk, sed
MoonBash 已在浏览器中上线。无 WASM，无服务端往返。
现在开始执行一组真实的中文任务演示数据流...
`;

const DEMO_APP_LOG = `2026-04-18T09:00:01Z INFO 启动: 初始化 parser
2026-04-18T09:00:02Z INFO 启动: 预加载虚拟文件系统
2026-04-18T09:00:03Z WARN 接口: 正在重试 /v1/sync
2026-04-18T09:00:04Z ERROR 接口: 上游超时 request_id=req-17
2026-04-18T09:00:05Z INFO 队列: 积压任务清空
2026-04-18T09:00:06Z ERROR Worker: 载荷解析失败 request_id=req-18
2026-04-18T09:00:07Z INFO Worker: 重试后恢复
`;

const DEMO_USERS_JSON = JSON.stringify(
  {
    users: [
      { id: 1, name: "阿周", plan: "专业版", region: "华东" },
      { id: 2, name: "林溪", plan: "免费版", region: "华北" },
      { id: 3, name: "米拉", plan: "专业版", region: "华南" },
      { id: 4, name: "小乔", plan: "团队版", region: "华东" },
      { id: 5, name: "任远", plan: "专业版", region: "西南" }
    ]
  },
  null,
  2
) + "\n";

const DEMO_REVENUE_CSV = `团队,月份,营收
北辰,2026-01,1200
北辰,2026-02,1350
云河,2026-01,980
云河,2026-02,1430
星塔,2026-01,1600
星塔,2026-02,1710
`;

const DEMO_NOTES_MD = `# 任务说明

- 浏览器运行时: MoonBit + JS host bridge
- 文件系统: 全虚拟内存实现
- 目标: 证明 MoonBash 能在浏览器里完成真实工作流，而不仅是命令存在校验
`;
globalThis.__moonbash_demo_runtime_libs = {
  Bash,
  defineCommand,
};

globalThis.__moonbash_demo_config_json = JSON.stringify({
  version: packageInfo.version,
  githubUrl: GITHUB_URL,
  docsUrl: DOCS_URL,
  welcomeText: WELCOME_TEXT,
  showcaseIntro: SHOWCASE_INTRO,
  initialCommand: "cat wtf-is-this.md",
  aboutText: ABOUT_TEXT,
  installText: INSTALL_TEXT,
  githubText: `${GITHUB_URL}\n`,
  verificationTitle: "Real Browser Verification",
  showcaseTitle: "Agent Mission / Browser Ops Console",
  defaultMode: "verification",
  verificationAutoStart: true,
  verificationInitialDelayMs: 900,
  commandNames: getCommandNames(),
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
    "/demo/logs/app.log": DEMO_APP_LOG,
    "/demo/data/users.json": DEMO_USERS_JSON,
    "/demo/data/revenue.csv": DEMO_REVENUE_CSV,
    "/demo/notes/mission.md": DEMO_NOTES_MD,
    "/demo/src/core/parser.mbt": "/// 中文演示: parser\nfn parse(input : String) -> String { input }\n",
    "/demo/src/core/interpreter.mbt": "/// 中文演示: interpreter\nfn run(script : String) -> String { script }\n",
    "/demo/src/commands/grep.mbt": "/// 中文演示: grep\nfn grep() -> Unit { () }\n",
    "/demo/src/commands/jq.mbt": "/// 中文演示: jq\nfn jq() -> Unit { () }\n",
    "/demo/src/fs/inmemory.mbt": "/// 中文演示: in-memory fs\nfn snapshot() -> Unit { () }\n",
  },
});

mount_demo();
