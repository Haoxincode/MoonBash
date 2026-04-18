// moon_bash Interpreter - Date builtin white-box tests

#cfg(target="js")
extern "js" fn test_set_wall_now_ms(text : String) =
  #| function(text) {
  #|   const value = Number(text);
  #|   globalThis.__moon_bash_wall_now = () => (Number.isFinite(value) ? value : 0);
  #| }

#cfg(not(target="js"))
fn test_set_wall_now_ms(_text : String) -> Unit {
  ()
}

#cfg(target="js")
extern "js" fn test_clear_wall_now_ms() =
  #| function() {
  #|   delete globalThis.__moon_bash_wall_now;
  #| }

#cfg(not(target="js"))
fn test_clear_wall_now_ms() -> Unit {
  ()
}

///|
fn test_date_context() -> ExecContext {
  ExecContext::new(@fs.InMemoryFs::new())
}

///|
test "date parses supported args" {
  match date_parse_args(["-u", "+%Y-%m-%d"]) {
    Ok(config) => {
      assert_true(config.use_utc)
      assert_eq(config.format, Some("%Y-%m-%d"))
    }
    Err(msg) => fail(msg)
  }
}

///|
test "date rejects unsupported option" {
  match date_parse_args(["-r"]) {
    Ok(_) => fail("expected error")
    Err(msg) => inspect(msg, content="date: unsupported option -- '-r'\n")
  }
}

///|
test "date default output uses wall clock and utc" {
  test_set_wall_now_ms("1435677542000")
  let ctx = test_date_context()
  ctx.builtin_date([])
  inspect(ctx.stdout_buf.to_string(), content="Tue Jun 30 15:19:02 UTC 2015\n")
  inspect(ctx.stderr_buf.to_string(), content="")
  inspect(ctx.exit_code, content="0")
  test_clear_wall_now_ms()
}

///|
test "date format directives cover common cases" {
  test_set_wall_now_ms("1435677542000")
  let ctx = test_date_context()
  ctx.builtin_date(["-u", "+%Y-%m-%d %H:%M:%S %s %Z %z"])
  inspect(
    ctx.stdout_buf.to_string(),
    content="2015-06-30 15:19:02 1435677542 UTC +0000\n",
  )
  inspect(ctx.exit_code, content="0")
  test_clear_wall_now_ms()
}
