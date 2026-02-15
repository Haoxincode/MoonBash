# MoonBash

**A zero-dependency, pure-memory POSIX Shell sandbox powered by MoonBit.**

MoonBash is a complete rewrite of [vercel-labs/just-bash](https://github.com/vercel-labs/just-bash) using [MoonBit](https://www.moonbitlang.com/), compiled to pure JavaScript with no WASM dependencies. It provides a secure, embeddable Bash interpreter for AI Agents, Serverless Edge functions, browser-based terminals, and any environment that needs sandboxed shell execution.

## Why MoonBash?

| Feature | just-bash (TS) | MoonBash (MoonBit) |
|---|---|---|
| Language | TypeScript | MoonBit -> Pure JS |
| Type Safety | Structural (TS) | Algebraic Data Types + Pattern Matching |
| ReDoS Protection | JS RegExp (vulnerable) | VM-based regex engine (immune) |
| Bundle Size | ~200KB+ | Target: <100KB |
| Cold Start | Fast | Faster (aggressive DCE) |
| WASM Required | No | No |
| API Compatible | N/A | 100% drop-in replacement |

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
│  │  80+ Built-in    │  │   Virtual Filesystem     │ │
│  │   Commands       │  │   (InMemoryFs/Overlay)   │ │
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
| [Commands](./COMMANDS.md) | All 80+ built-in command specifications |
| [Ecosystem Mapping](./ECOSYSTEM_COMMAND_MAPPING.md) | Command-to-library implementation strategy and FFI boundary |
| [Filesystem](./FILESYSTEM.md) | Virtual filesystem design and implementation |
| [Security](./SECURITY.md) | Sandbox security model and threat mitigation |
| [FFI & Interop](./FFI.md) | MoonBit-JavaScript interop design |
| [Roadmap](./ROADMAP.md) | Development phases and milestones |

## License

Apache-2.0
