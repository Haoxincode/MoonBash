// MoonBash Commands - Shell builtins
// echo, true, false, cd, pwd

/// echo: print arguments to stdout
fn cmd_echo(ctx : CommandContext) -> @ast.ExecResult {
  let buf = StringBuilder::new()
  let mut no_newline = false
  let mut interpret_escapes = false
  let mut start = 0

  // Parse flags
  while start < ctx.args.length() {
    let arg = ctx.args[start]
    if arg == "-n" {
      no_newline = true
      start += 1
    } else if arg == "-e" {
      interpret_escapes = true
      start += 1
    } else if arg == "-E" {
      interpret_escapes = false
      start += 1
    } else if arg == "-ne" || arg == "-en" {
      no_newline = true
      interpret_escapes = true
      start += 1
    } else {
      break
    }
  }

  // Output args joined by spaces
  for i = start; i < ctx.args.length(); i = i + 1 {
    if i > start {
      buf.write_char(' ')
    }
    if interpret_escapes {
      buf.write_string(process_echo_escapes(ctx.args[i]))
    } else {
      buf.write_string(ctx.args[i])
    }
  }
  if not(no_newline) {
    buf.write_char('\n')
  }
  @ast.ExecResult::ok(buf.to_string())
}

/// Process escape sequences for echo -e
fn process_echo_escapes(s : String) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let ch = s[i].to_int().unsafe_to_char()
    if ch == '\\' && i + 1 < s.length() {
      let next = s[i + 1].to_int().unsafe_to_char()
      match next {
        'n' => { buf.write_char('\n'); i += 2 }
        't' => { buf.write_char('\t'); i += 2 }
        'r' => { buf.write_char('\r'); i += 2 }
        '\\' => { buf.write_char('\\'); i += 2 }
        'a' => { buf.write_char('\u0007'); i += 2 }
        'b' => { buf.write_char('\u0008'); i += 2 }
        'f' => { buf.write_char('\u000C'); i += 2 }
        'v' => { buf.write_char('\u000B'); i += 2 }
        _ => { buf.write_char(ch); i += 1 }
      }
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

/// true: return success
fn cmd_true(_ctx : CommandContext) -> @ast.ExecResult {
  @ast.ExecResult::new(exit_code=0)
}

/// false: return failure
fn cmd_false(_ctx : CommandContext) -> @ast.ExecResult {
  @ast.ExecResult::new(exit_code=1)
}

/// cd: change directory
fn cmd_cd(ctx : CommandContext) -> @ast.ExecResult {
  let target = if ctx.args.length() == 0 {
    ctx.env.get("HOME").unwrap_or("/home/user")
  } else if ctx.args[0] == "-" {
    ctx.env.get("OLDPWD").unwrap_or(ctx.cwd)
  } else {
    ctx.args[0]
  }
  let resolved = try {
    @fs.resolve_path(ctx.cwd, target)
  } catch {
    @fs.FsError(msg) => return @ast.ExecResult::err("cd: \{msg}\n")
  }
  // Verify the directory exists
  match ctx.fs.entries.get(resolved) {
    Some(@fs.FsEntry::Directory(_)) =>
      // Note: The interpreter needs to update cwd after this returns.
      // We indicate success. The interpreter reads the target from args.
      @ast.ExecResult::ok("")
    Some(_) => @ast.ExecResult::err("cd: not a directory: \{target}\n")
    None => @ast.ExecResult::err("cd: no such file or directory: \{target}\n")
  }
}

/// pwd: print working directory
fn cmd_pwd(ctx : CommandContext) -> @ast.ExecResult {
  @ast.ExecResult::ok(ctx.cwd + "\n")
}
