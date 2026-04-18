# MoonBash

MoonBash is a pure-memory POSIX shell sandbox written in MoonBit. It compiles to pure JavaScript, keeps execution inside an in-memory filesystem, and is designed for embedding in AI agents, browser terminals, and serverless runtimes.

This MoonBit module publishes the core runtime packages. The TypeScript wrapper and website demo stay in the GitHub repository and are excluded from the mooncakes package.

## Install

```bash
moon add Haoxincode/moonbash
```

## Public package

The main entry package is:

```text
Haoxincode/moonbash/lib/entry
```

It exports:

- `execute`
- `execute_with_fs`
- `execute_with_state`

## Example

Add the dependency in your `moon.pkg`:

```moonbit
import {
  "Haoxincode/moonbash/lib/entry" @moonbash,
}
```

Then call it from MoonBit:

```moonbit
fn run_demo() -> Unit {
  let result = @moonbash.execute("echo hello from moonbash")
  println(result)
}
```

## Repository

- GitHub: <https://github.com/Haoxincode/MoonBash>
- Docs: <https://github.com/Haoxincode/MoonBash/tree/main/docs>
