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

- `src/website/website.mbt` - MoonBit mount layer that creates the DOM terminal UI and wires interaction
- `src/wrapper/browser.ts` - browser-facing wrapper exports used by the demo bundle
- `examples/website/main.js` - demo bootstrap that injects content, commands, and initial files

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

## Goal

This demo is meant to prove usability, not just compilation:

- MoonBash can be embedded as a real browser terminal
- the browser runtime can explore a preloaded virtual filesystem interactively
- MoonBit can own part of the frontend integration layer, not only the shell core
- the website can autoplay a real verification pass and surface concrete pass/fail results in the UI
