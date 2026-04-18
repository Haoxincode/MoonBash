# MoonBash Website Demo

This demo recreates the `justbash.dev` terminal experience with MoonBash running in the browser.

## What It Includes

- a full-screen terminal-style landing page
- MoonBash running entirely in-memory in the browser
- preloaded repository docs like `README.md`, `ARCHITECTURE.md`, `API.md`, `ROADMAP.md`, and `AGENTS.md`
- custom commands: `about`, `install`, `github`
- command history and tab completion in the browser UI
- automatic real verification on load: command-by-command registry checks plus smoke tests

## Architecture

The demo is split into three pieces:

- `src/website/*.mbt` - MoonBit-led website runtime:
  - `config.mbt` parses injected config and builds verification plans
  - `dom_helpers.mbt` creates and updates DOM with `tiye/dom-ffi`
  - `app.mbt` owns shell state, history, tab completion, autoplay verification, and async flow
  - `website.mbt` is the mount entry point
- `src/website/bridge.mbt` - thin host bridge for `Bash` runtime creation and the few browser APIs not yet wrapped ergonomically
- `src/wrapper/browser.ts` - browser-facing wrapper exports used by the demo bundle
- `examples/website/main.js` - thin bootstrap that injects config, docs, files, and wrapper exports into `globalThis`

Build output lands in `examples/website/dist/`.

## Build

```bash
pnpm build:website
```

This runs:

1. `moon build --target js`
2. an `esbuild` browser bundle for `examples/website/main.js`
3. static asset copy into `examples/website/dist/`

## Serve

```bash
pnpm serve:website
```

Then open <http://localhost:4173>.

## Deploy To Vercel

This repository can be deployed to Vercel as a static site.

Included config:

- `vercel.json` sets the build command and output directory
- `scripts/vercel-build.sh` installs MoonBit in the build environment if needed, then runs `pnpm build:website`

Expected Vercel behavior:

1. dependencies are installed from the repo lockfile
2. MoonBit is installed during the build step if it is not already available
3. the static output is published from `examples/website/dist`

If you import the repository into Vercel, keep the project root at the repository root.

## Goal

This demo is meant to prove usability, not just compilation:

- MoonBash can be embedded as a real browser terminal
- the browser runtime can explore a preloaded virtual filesystem interactively
- MoonBit can own part of the frontend integration layer, not only the shell core
- the website can autoplay a real verification pass and surface concrete pass/fail results in the UI
- the async execution path can be driven from MoonBit via `moonbitlang/async/js_async`, instead of staying in ad-hoc JS promise chains
