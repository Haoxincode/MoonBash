# MoonBash Built-in Commands

MoonBash implements 80+ Unix commands as pure MoonBit code. Each command runs entirely in-memory with no system calls.

## Command Categories

### File Operations (14)

| Command | Description | Complexity |
|---|---|---|
| `cat` | Concatenate and display files | Low |
| `cp` | Copy files and directories | Medium |
| `file` | Determine file type | Low |
| `ln` | Create symbolic links | Low |
| `ls` | List directory contents | Medium |
| `mkdir` | Create directories | Low |
| `mv` | Move/rename files | Medium |
| `readlink` | Print resolved symbolic link | Low |
| `rm` | Remove files and directories | Low |
| `rmdir` | Remove empty directories | Low |
| `split` | Split file into pieces | Medium |
| `stat` | Display file status | Low |
| `touch` | Create/update file timestamps | Low |
| `tree` | Display directory tree | Medium |

### Text Processing (30+)

| Command | Description | Complexity |
|---|---|---|
| `awk` | Pattern scanning and processing | **Very High** |
| `base64` | Base64 encode/decode | Low |
| `column` | Columnate lists | Medium |
| `comm` | Compare sorted files line by line | Medium |
| `cut` | Remove sections from lines | Medium |
| `diff` | Compare files line by line | High |
| `expand` | Convert tabs to spaces | Low |
| `fold` | Wrap lines to specified width | Low |
| `grep` | Search text patterns (+ `egrep`, `fgrep`) | High |
| `head` | Output first part of files | Low |
| `join` | Join lines on a common field | Medium |
| `md5sum` | Compute MD5 hash | Medium |
| `nl` | Number lines | Low |
| `od` | Octal dump | Medium |
| `paste` | Merge lines of files | Low |
| `printf` | Format and print data | Medium |
| `rev` | Reverse lines | Low |
| `rg` | Ripgrep-compatible search | High |
| `sed` | Stream editor | **Very High** |
| `sha1sum` | Compute SHA-1 hash | Medium |
| `sha256sum` | Compute SHA-256 hash | Medium |
| `sort` | Sort lines of text | High |
| `strings` | Find printable strings | Low |
| `tac` | Concatenate and print in reverse | Low |
| `tail` | Output last part of files | Medium |
| `tr` | Translate characters | Medium |
| `unexpand` | Convert spaces to tabs | Low |
| `uniq` | Report or omit repeated lines | Medium |
| `wc` | Word, line, character count | Low |
| `xargs` | Build and execute commands | High |

### Data Processing (4)

| Command | Description | Complexity |
|---|---|---|
| `jq` | JSON processor | **Very High** |
| `yq` | YAML/XML/TOML/CSV processor | High |
| `xan` | CSV processor | High |
| `sqlite3` | SQL database (optional, WASM) | N/A |

### Compression & Archives (4)

| Command | Description | Complexity |
|---|---|---|
| `gzip` | Compress files | Medium |
| `gunzip` | Decompress files | Medium |
| `zcat` | View compressed files | Medium |
| `tar` | Archive files | High |

### Navigation & Environment (13)

| Command | Description | Complexity |
|---|---|---|
| `basename` | Strip directory from path | Low |
| `cd` | Change directory (builtin) | Low |
| `dirname` | Strip filename from path | Low |
| `du` | Estimate file space usage | Medium |
| `echo` | Display text (builtin) | Low |
| `env` | Print environment | Low |
| `export` | Set environment variables (builtin) | Low |
| `find` | Search for files | High |
| `hostname` | Show hostname | Low |
| `printenv` | Print environment variables | Low |
| `pwd` | Print working directory (builtin) | Low |
| `tee` | Read stdin and write to files | Low |
| `which` | Locate a command | Low |

### Shell Utilities (17)

| Command | Description | Complexity |
|---|---|---|
| `alias` | Define command aliases (builtin) | Low |
| `bash` | Execute bash sub-script | Medium |
| `chmod` | Change file mode | Low |
| `clear` | Clear terminal (no-op in sandbox) | Low |
| `date` | Display date and time | Medium |
| `expr` | Evaluate expressions | Medium |
| `false` | Return failure exit code | Low |
| `help` | Display help text | Low |
| `history` | Command history (builtin) | Low |
| `seq` | Print number sequence | Low |
| `sh` | Execute shell script | Medium |
| `sleep` | Delay execution | Low |
| `time` | Time a command | Low |
| `timeout` | Run command with time limit | Medium |
| `true` | Return success exit code | Low |
| `unalias` | Remove alias (builtin) | Low |
| `whoami` | Print current user | Low |

### Network (2, opt-in)

| Command | Description | Complexity |
|---|---|---|
| `curl` | Transfer data from URLs | High |
| `html-to-markdown` | Convert HTML to Markdown | Medium |

## Implementation Priority

### Phase 1: Core (MVP)

Essential commands for basic shell operation:

```
echo, cat, cd, pwd, ls, mkdir, rm, cp, mv, touch,
head, tail, wc, sort, uniq, grep, printf, tee,
true, false, env, export, which, basename, dirname,
read, test/[, seq, date, sleep, expr
```

### Phase 2: Text Processing

Commands needed for data pipeline use cases:

```
awk, sed, cut, tr, paste, join, comm, diff,
fold, expand, unexpand, nl, rev, tac, column,
xargs, find, du, split, strings, od
```

### Phase 3: Data & Advanced

Commands for structured data processing:

```
jq, yq, xan, base64, md5sum, sha1sum, sha256sum,
gzip, gunzip, zcat, tar, rg, stat, file, tree,
ln, readlink, rmdir, chmod, hostname, whoami,
timeout, time, help, history, clear
```

### Phase 4: Network

Commands requiring network access (opt-in):

```
curl, html-to-markdown
```

## Command Implementation Pattern

Each command in MoonBit follows a consistent pattern:

```moonbit
// commands/file_ops/cat.mbt

pub fn cat_command(args : Array[String], ctx : CommandContext) -> ExecResult {
  // 1. Parse options
  let opts = parse_cat_options(args)

  // 2. Validate arguments
  if opts.files.is_empty() {
    // Read from stdin
    return ExecResult::ok(ctx.stdin)
  }

  // 3. Execute
  let output = @buffer.new()
  for file in opts.files {
    match ctx.fs.read_file(resolve_path(ctx.cwd, file)) {
      Ok(content) => {
        if opts.number_lines {
          number_lines(content, output)
        } else {
          output.write_string(content)
        }
      }
      Err(e) => {
        return ExecResult::err("cat: \{file}: No such file or directory\n")
      }
    }
  }

  ExecResult::ok(output.to_string())
}
```

## Complex Command Notes

### `awk` Implementation

AWK requires a complete sub-interpreter:
- Lexer and parser for AWK syntax
- Pattern matching engine (BEGIN, END, /regex/, expressions)
- Field splitting (`$0`, `$1`, `$NF`)
- Built-in variables (`NR`, `NF`, `FS`, `RS`, `OFS`, `ORS`)
- Built-in functions (`length`, `substr`, `split`, `gsub`, `sub`, `match`, `printf`, `sprintf`)
- User-defined functions
- Associative arrays
- Iteration limit enforcement

### `sed` Implementation

SED requires a stream processing engine:
- Address types (line number, regex, range, step)
- Commands: `s`, `d`, `p`, `a`, `i`, `c`, `y`, `q`, `r`, `w`, `b`, `t`, `T`
- Hold space / pattern space management
- Branch labels and loops
- Multi-line operations (`N`, `P`, `D`)
- Iteration limit enforcement to prevent infinite loops

### `jq` Implementation

JQ requires a JSON query interpreter:
- Parser for jq filter syntax
- Identity (`.`), field access (`.field`), array index (`.[0]`)
- Pipe (`|`), comma (`,`)
- Conditionals (`if-then-else`)
- String interpolation (`\(expr)`)
- Built-in functions (`length`, `keys`, `values`, `map`, `select`, `sort_by`, `group_by`, `unique`, `flatten`, `range`, `type`, `empty`, `error`, `env`, `path`, `getpath`, `setpath`, `delpaths`, etc.)
- `try-catch`, `?//` (alternative operator)
- `@base64`, `@csv`, `@tsv`, `@html`, `@json`, `@text`, `@uri` format strings
- Variable binding (`as $var`)
- Reduce (`reduce .[] as $x (init; update)`)
- `limit`, `first`, `last`, `nth`
- Object construction, array construction
- Recursive descent (`..`)
- Iteration limit enforcement

### `grep` Implementation

- Basic regex (BRE) - default
- Extended regex (ERE) - `-E` / `egrep`
- Fixed string matching - `-F` / `fgrep`
- Case insensitive - `-i`
- Invert match - `-v`
- Count matches - `-c`
- Line numbers - `-n`
- Filenames - `-l`, `-L`
- Context lines - `-A`, `-B`, `-C`
- Recursive search - `-r`, `-R`
- Word match - `-w`
- Line match - `-x`
- Quiet mode - `-q`
- Multiple patterns - `-e`
- Pattern file - `-f`
- Binary file handling
- Color output (where applicable)

Uses MoonBit's `@regexp` library (VM-based, ReDoS-immune) for pattern matching.
