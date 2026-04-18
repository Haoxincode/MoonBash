// moon_bash Interpreter - Date builtin

///|
priv struct DateConfig {
  use_utc : Bool
  format : String?
}

///|
fn date_pad2(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn date_pad2_space(value : Int) -> String {
  if value < 10 {
    " " + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn date_weekday_short(weekday : @time.Weekday) -> String {
  match weekday {
    Monday => "Mon"
    Tuesday => "Tue"
    Wednesday => "Wed"
    Thursday => "Thu"
    Friday => "Fri"
    Saturday => "Sat"
    Sunday => "Sun"
  }
}

///|
fn date_weekday_long(weekday : @time.Weekday) -> String {
  match weekday {
    Monday => "Monday"
    Tuesday => "Tuesday"
    Wednesday => "Wednesday"
    Thursday => "Thursday"
    Friday => "Friday"
    Saturday => "Saturday"
    Sunday => "Sunday"
  }
}

///|
fn date_month_short(month : Int) -> String {
  match month {
    1 => "Jan"
    2 => "Feb"
    3 => "Mar"
    4 => "Apr"
    5 => "May"
    6 => "Jun"
    7 => "Jul"
    8 => "Aug"
    9 => "Sep"
    10 => "Oct"
    11 => "Nov"
    12 => "Dec"
    _ => ""
  }
}

///|
fn date_month_long(month : Int) -> String {
  match month {
    1 => "January"
    2 => "February"
    3 => "March"
    4 => "April"
    5 => "May"
    6 => "June"
    7 => "July"
    8 => "August"
    9 => "September"
    10 => "October"
    11 => "November"
    12 => "December"
    _ => ""
  }
}

///|
fn date_weekday_sunday_index(weekday : @time.Weekday) -> Int {
  match weekday {
    Sunday => 0
    Monday => 1
    Tuesday => 2
    Wednesday => 3
    Thursday => 4
    Friday => 5
    Saturday => 6
  }
}

///|
fn date_weekday_monday_index(weekday : @time.Weekday) -> Int {
  match weekday {
    Monday => 1
    Tuesday => 2
    Wednesday => 3
    Thursday => 4
    Friday => 5
    Saturday => 6
    Sunday => 7
  }
}

///|
fn date_parse_args(args : Array[String]) -> Result[DateConfig, String] {
  let mut use_utc = false
  let mut format : String? = None
  let mut parsing_options = true
  for arg in args {
    if parsing_options && arg == "--" {
      parsing_options = false
      continue
    }
    if parsing_options &&
      (arg == "-u" || arg == "--utc" || arg == "--universal") {
      use_utc = true
      continue
    }
    if arg.length() > 0 && arg[0].to_int().unsafe_to_char() == '+' {
      if !(format is None) {
        return Err("date: extra operand '\{arg}'\n")
      }
      format = Some(arg.view(start_offset=1).to_string())
      parsing_options = false
      continue
    }
    if parsing_options && arg.length() > 1 && arg[0].to_int().unsafe_to_char() == '-' {
      return Err("date: unsupported option -- '\{arg}'\n")
    }
    return Err("date: extra operand '\{arg}'\n")
  }
  Ok({ use_utc, format })
}

///|
fn date_current_datetime_utc() -> @time.ZonedDateTime {
  let now_ms = @ffi.wall_now_ms_sync()
  let second = now_ms / 1000L
  let millisecond = (now_ms % 1000L).to_int()
  let nanosecond = if millisecond < 0 { 0 } else { millisecond * 1_000_000 }
  @time.unix(second, nanosecond=nanosecond, zone=@time.utc_zone) catch {
    _ => @time.unix(0L, zone=@time.utc_zone) catch { _ => abort("date: failed to build UTC datetime") }
  }
}

///|
fn date_default_output(dt : @time.ZonedDateTime) -> String {
  "\{date_weekday_short(dt.weekday())} \{date_month_short(dt.month())} \{date_pad2_space(dt.day())} \{date_pad2(dt.hour())}:\{date_pad2(dt.minute())}:\{date_pad2(dt.second())} UTC \{dt.year()}"
}

///|
fn date_format_output(dt : @time.ZonedDateTime, format : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < format.length() {
    let ch = format[i].to_int().unsafe_to_char()
    if ch != '%' || i + 1 >= format.length() {
      out.write_char(ch)
      i += 1
      continue
    }
    let code = format[i + 1].to_int().unsafe_to_char()
    match code {
      '%' => out.write_char('%')
      'Y' => out.write_string(dt.year().to_string())
      'm' => out.write_string(date_pad2(dt.month()))
      'd' => out.write_string(date_pad2(dt.day()))
      'e' => out.write_string(date_pad2_space(dt.day()))
      'H' => out.write_string(date_pad2(dt.hour()))
      'M' => out.write_string(date_pad2(dt.minute()))
      'S' => out.write_string(date_pad2(dt.second()))
      'a' => out.write_string(date_weekday_short(dt.weekday()))
      'A' => out.write_string(date_weekday_long(dt.weekday()))
      'b' => out.write_string(date_month_short(dt.month()))
      'B' => out.write_string(date_month_long(dt.month()))
      'F' => out.write_string("\{dt.year()}-\{date_pad2(dt.month())}-\{date_pad2(dt.day())}")
      'T' => out.write_string("\{date_pad2(dt.hour())}:\{date_pad2(dt.minute())}:\{date_pad2(dt.second())}")
      's' => out.write_string(dt.to_unix_second().to_string())
      'u' => out.write_string(date_weekday_monday_index(dt.weekday()).to_string())
      'w' => out.write_string(date_weekday_sunday_index(dt.weekday()).to_string())
      'Z' => out.write_string("UTC")
      'z' => out.write_string("+0000")
      _ => {
        out.write_char('%')
        out.write_char(code)
      }
    }
    i += 2
  }
  out.to_string()
}

///|
fn ExecContext::builtin_date(self : ExecContext, args : Array[String]) -> Unit {
  let config = match date_parse_args(args) {
    Ok(config) => config
    Err(msg) => {
      self.stderr_buf.write_string(msg)
      self.exit_code = 1
      return
    }
  }
  let dt = if config.use_utc {
    date_current_datetime_utc()
  } else {
    // Keep default output deterministic and non-leaky by using UTC.
    date_current_datetime_utc()
  }
  let output = match config.format {
    Some(format) => date_format_output(dt, format)
    None => date_default_output(dt)
  }
  self.stdout_buf.write_string(output + "\n")
  self.exit_code = 0
}
