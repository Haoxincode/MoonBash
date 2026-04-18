// moon_bash Commands - Network tests

///|
fn test_network_context(
  args : Array[String],
  stdin_content? : String = "",
) -> CommandContext {
  { args, stdin_content, cwd: "/home/user", env: {}, fs: @fs.InMemoryFs::new() }
}

///|
test "parse curl args with attached short options" {
  match
    net_parse_curl_args([
      "-siL", "-XPOST", "-Haccept: text/html", "-H", "x-id: 1", "--data=hello", "-o",
      "/tmp/out.txt", "https://example.com",
    ]) {
    Ok(config) => {
      assert_eq(config.http_method, "POST")
      assert_true(config.include_headers)
      assert_true(config.silent)
      assert_eq(config.output_path, Some("/tmp/out.txt"))
      assert_eq(config.body, Some("hello"))
      assert_eq(config.url, Some("https://example.com"))
      assert_eq(config.headers.length(), 2)
      assert_eq(config.headers[0], ("accept", "text/html"))
      assert_eq(config.headers[1], ("x-id", "1"))
    }
    Err(result) => fail(result.stderr)
  }
}

///|
test "parse curl args rejects unsupported option" {
  match net_parse_curl_args(["--wat", "https://example.com"]) {
    Ok(_) => fail("expected unsupported option")
    Err(result) => {
      assert_eq(result.stderr, "curl: unsupported option -- '--wat'\n")
      assert_eq(result.exit_code, 2)
    }
  }
}

///|
test "parse curl args keeps dash positional after double dash" {
  match net_parse_curl_args(["--", "-literal-url"]) {
    Ok(config) => assert_eq(config.url, Some("-literal-url"))
    Err(result) => fail(result.stderr)
  }
}

///|
test "parse html-to-markdown args" {
  match
    net_parse_html_to_markdown_args([
      "-o", "/tmp/page.md", "--url=https://example.com/page",
    ]) {
    Ok(config) => {
      assert_eq(config.output_path, Some("/tmp/page.md"))
      assert_eq(config.source_url, Some("https://example.com/page"))
    }
    Err(result) => fail(result.stderr)
  }
}

///|
test "parse html-to-markdown rejects unsupported option" {
  match net_parse_html_to_markdown_args(["--wat"]) {
    Ok(_) => fail("expected unsupported option")
    Err(result) =>
      assert_eq(
        result.stderr,
        "html-to-markdown: unsupported option -- '--wat'\n",
      )
  }
}

///|
test "normalize request url accepts https" {
  match net_normalize_request_url("https://Example.com:443/Foo?q=1#frag") {
    Ok(url) => {
      assert_true(url.has_prefix("https://example.com"))
      assert_true(url.has_prefix("https://"))
    }
    Err(msg) => fail(msg)
  }
}

///|
test "normalize request url rejects invalid scheme" {
  match net_normalize_request_url("mailto:test@example.com") {
    Ok(_) => fail("expected unsupported scheme")
    Err(msg) => assert_eq(msg, "unsupported URL scheme")
  }
}

///|
test "cmd curl reports missing url" {
  let result = cmd_curl(test_network_context(["-s"]))
  assert_eq(result.stderr, "curl: no URL specified\n")
  assert_eq(result.exit_code, 2)
}

///|
test "cmd html-to-markdown reports missing input" {
  let result = cmd_html_to_markdown(test_network_context([]))
  assert_eq(result.stderr, "html-to-markdown: missing input\n")
  assert_eq(result.exit_code, 1)
}
