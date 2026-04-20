# MoonBash

**A zero-dependency, pure-memory POSIX Shell sandbox powered by MoonBit.**

MoonBash is a complete rewrite of [vercel-labs/just-bash](https://github.com/vercel-labs/just-bash) using [MoonBit](https://www.moonbitlang.com/), compiled to pure JavaScript with no WASM dependencies. It provides a secure, embeddable Bash interpreter for AI Agents, Serverless Edge functions, browser-based terminals, and any environment that needs sandboxed shell execution.

## Why MoonBash?

| Feature | just-bash (TS) | MoonBash (MoonBit) |
|---|---|---|
| Language | TypeScript | MoonBit -> Pure JS |
| Type Safety | Structural (TS) | Algebraic Data Types + Pattern Matching |
| ReDoS Protection | JS RegExp (vulnerable) | VM-based regex engine (immune) |
| Commands | ~30 | 87 (incl. awk, sed, jq, tar, diff, gzip) |
| Bundle Size | ~200KB+ | **245 KB** gzip / 997 KB minified |
| Cold Start | Fast | Faster (sync init, no WASM instantiate) |
| WASM Required | No | No |
| API Surface Compatible | N/A | 100% drop-in replacement |

Status note (as of 2026-04-20): command coverage is complete (`87/87`) and comparison tests are at `523/523` (`100%`). Security test suites are fully passing, gzip/gunzip/zcat use real DEFLATE compression via `gmlewis/gzip`, and the browser website demo now ships under `examples/website/` with MoonBit owning the runtime flow in `src/website/*.mbt`. Spec compatibility hardening remains in progress. See `docs/ROADMAP.md`.

## Package Size

Current npm package measurements, taken on `2026-04-20` from the actual release build (`moon -C src build --target js --release`), `vp pack`, and `npm pack --dry-run` outputs:

| Artifact | Size | Notes |
|-------|------|-----------|
| `dist/index.mjs` | 4.56 MB | raw ESM bundle produced by `vp pack` |
| `dist/index.mjs` (gzip) | 663 KB | approximate compressed transfer size |
| published npm tarball | 650 KB | `moon-bash-0.1.0.tgz` from `npm pack --dry-run` |
| unpacked npm payload | 4.57 MB | release bundle plus declarations, no sourcemaps published |

Why this is still larger than the older `997 KB` / `245 KB` figures sometimes cited in project notes:

- those numbers refer to a separately minified MoonBit release artifact benchmark, not the current npm package emitted by `vp pack`
- the npm package no longer ships sourcemaps; the tarball now contains only `dist/index.mjs`, `dist/index.d.mts`, and `package.json`
- the shipped ESM bundle is optimized for correct packaging and TypeScript consumption first; more aggressive minification is a separate tradeoff

## Core Value Propositions

1. **Zero Dependencies** - Compiles to a single pure JS file, no WASM, no native binaries
2. **Memory Safe** - MoonBit's type system prevents null pointer crashes and buffer overflows
3. **ReDoS Immune** - Built-in VM-based regex engine eliminates catastrophic backtracking
4. **API Compatible** - Drop-in replacement for `just-bash` with identical TypeScript API
5. **Multi-Target** - Same MoonBit source compiles to JS (npm), WASM (Python/Rust), and native

## Target Environments

- **AI Agent Frameworks** - LangChain, AutoGen, OpenDevin, Claude Code
- **Serverless Edge** - Vercel Edge, Cloudflare Workers, Deno Deploy
- **Browser** - Online coding education, interactive documentation
- **Embedded** - Game engines, cross-platform build tools, CI/CD pipelines

## Quick Start

```typescript
import { Bash } from "moon-bash";

const bash = new Bash({
  env: { USER: "agent" },
});

const result = await bash.exec('echo "Hello from MoonBash!" | tr a-z A-Z');
console.log(result.stdout); // "HELLO FROM MOONBASH!\n"
console.log(result.exitCode); // 0
```

## Build & Packaging

MoonBash currently has three distinct build outputs:

- **npm package** - `vp run build` runs `moon -C src build --target js --release && vp pack`, bundling [`src/wrapper/index.ts`](../src/wrapper/index.ts) into an ESM package at `dist/`. The published entrypoints are `dist/index.mjs` and `dist/index.d.mts`; sourcemaps are not shipped in the npm package.
- **MoonBit / mooncakes package** - the pure MoonBit runtime is packaged from `src/` using [`src/moon.mod.json`](../src/moon.mod.json). The TypeScript wrapper and browser demo are excluded from that package, and MoonBit publish artifacts are produced under `src/_build/publish/`.
- **Browser demo** - `vp run build:website` builds the static site into `examples/website/dist/`.

Useful commands:

- `vp run build:mbt` - compile the MoonBit core to JavaScript in `release` mode
- `vp run build:ts` - bundle the TypeScript wrapper into the npm package under `dist/`
- `vp run build` - run both steps for the npm package
- `vp run build:website` - build the browser demo bundle

Build pipeline in practice:

```text
MoonBit (.mbt) -> moon -C src build --target js --release -> generated JS in src/_build/...
                -> src/wrapper/index.ts -> vp pack -> dist/index.mjs + dist/index.d.mts
                -> examples/website/main.js + src/website -> vp build -c vite.website.config.ts -> examples/website/dist/
```

## Browser Demo

MoonBash now includes a browser demo that recreates the `justbash.dev` terminal experience, but uses MoonBash as the runtime.

Key pieces:

- `src/website/` - MoonBit package for DOM creation, browser state, async command flow, and verification playback
- `src/wrapper/browser.ts` - browser-friendly wrapper exports exposing `Bash`, `defineCommand`, and related APIs
- `examples/website/main.js` - thin bootstrap that injects config/data into `globalThis`
- `examples/website/` - static website assets and bundle output

Build and run it locally:

```bash
vp run build:website
vp run serve:website
```

Then open <http://localhost:4173>.

What the demo proves:

- MoonBash can run entirely in the browser as pure JavaScript
- the in-memory filesystem can preload real repository docs for interactive exploration
- custom commands such as `about`, `install`, and `github` can be layered on top without changing the MoonBit core
- MoonBit can own the website runtime itself, not just the shell core, while keeping JS as a thin host/config bridge

See [`examples/website/README.md`](../examples/website/README.md) for the demo-specific README.

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  TypeScript API Layer                │
│         (100% compatible with just-bash API)         │
├─────────────────────────────────────────────────────┤
│                  MoonBit Core Engine                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐ │
│  │  Lexer   │→ │  Parser  │→ │   AST Evaluator   │ │
│  │(lexmatch)│  │(ADT+PM)  │  │(pattern matching) │ │
│  └──────────┘  └──────────┘  └───────────────────┘ │
│  ┌──────────────────┐  ┌──────────────────────────┐ │
│  │  87 Built-in     │  │   Virtual Filesystem     │ │
│  │   Commands       │  │ (InMemoryFs + AgentFS)   │ │
│  └──────────────────┘  └──────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│              moon build --target js                  │
│          Pure JavaScript Output (no WASM)            │
└─────────────────────────────────────────────────────┘
```

## Documentation Index

| Document | Description |
|---|---|
| [Architecture](./ARCHITECTURE.md) | System architecture and module design |
| [API Specification](./API.md) | Public API surface and type definitions |
| [Commands](./COMMANDS.md) | All 87 built-in command specifications |
| [Ecosystem Mapping](./ECOSYSTEM_COMMAND_MAPPING.md) | Command-to-library implementation strategy and FFI boundary |
| [Filesystem](./FILESYSTEM.md) | Virtual filesystem design and implementation |
| [Security](./SECURITY.md) | Sandbox security model and threat mitigation |
| [FFI & Interop](./FFI.md) | MoonBit-JavaScript interop design |
| [Roadmap](./ROADMAP.md) | Development phases and milestones |
| [`examples/website/README.md`](../examples/website/README.md) | Browser demo structure, build, and local serving |

## License

Apache-2.0
