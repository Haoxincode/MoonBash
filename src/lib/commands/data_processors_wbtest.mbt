// moon_bash Commands - Data processor white-box tests

///|
fn test_data_processors_context(
  args : Array[String],
  stdin_content? : String = "",
) -> CommandContext {
  { args, stdin_content, cwd: "/home/user", env: {}, fs: @fs.InMemoryFs::new() }
}

///|
fn test_data_processors_csv() -> String {
  "name,score\nalice,10\nbob,20\ncyd,30\n"
}

///|
test "xan slice parses start and length options" {
  let config = xan_slice_parse_args(["slice", "-i", "1", "-l", "2", "scores.csv"])
  assert_eq(config.start, 1)
  assert_eq(config.length, Some(2))
  assert_eq(config.file_path, Some("scores.csv"))
}

///|
test "xan slice ignores unsupported flags and missing values" {
  let config = xan_slice_parse_args(["slice", "-z", "-i", "scores.csv"])
  assert_eq(config.start, 0)
  assert_eq(config.length, None)
  assert_eq(config.file_path, None)
}

///|
test "xan slice uses last file positional" {
  let config = xan_slice_parse_args(["slice", "first.csv", "second.csv"])
  assert_eq(config.file_path, Some("second.csv"))
}

///|
test "xan slice reads from stdin" {
  let result = xan_slice(
    test_data_processors_context(
      ["slice", "-i", "1", "-l", "1"],
      stdin_content=test_data_processors_csv(),
    ),
  )
  assert_eq(result.stderr, "")
  assert_eq(result.stdout, "name,score\nbob,20\n")
}

///|
test "xan slice reads from file" {
  let ctx = test_data_processors_context(["slice", "-i", "0", "-l", "2", "scores.csv"])
  ctx.fs.write_file("/home/user/scores.csv", test_data_processors_csv())
  let result = xan_slice(ctx)
  assert_eq(result.stderr, "")
  assert_eq(result.stdout, "name,score\nalice,10\nbob,20\n")
}
