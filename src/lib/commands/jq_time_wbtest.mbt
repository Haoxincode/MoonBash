// jq and touch time compatibility white-box tests

///|
test "jq date compat computes gmtime generically" {
  match jq_compat_functions_dates("gmtime", jq_json_from_int(1425599507)) {
    Some([value]) => inspect(value.stringify(indent=0), content="[2015,2,5,23,51,47,4,63]")
    _ => fail("expected gmtime result")
  }
}

///|
test "jq date compat computes strptime and mktime generically" {
  match jq_compat_functions_dates(
    "strptime(\"%Y-%m-%dT%H:%M:%SZ\")|mktime",
    Json::string("2015-03-05T23:51:47Z"),
  ) {
    Some([value]) => inspect(value.stringify(indent=0), content="1425599507")
    _ => fail("expected strptime/mktime result")
  }
}

///|
test "jq date compat computes long strftime from unix timestamp" {
  match jq_compat_functions_dates(
    "strftime(\"%A, %B %d, %Y\")",
    jq_json_from_int(1435677542),
  ) {
    Some([Json::String(value)]) => inspect(value, content="Tuesday, June 30, 2015")
    _ => fail("expected long strftime result")
  }
}

///|
test "touch date parsing validates real calendar dates" {
  assert_true(!(cmd_touch_parse_date_value("2024-02-29") is None))
  assert_true(cmd_touch_parse_date_value("2023-02-29") is None)
}
