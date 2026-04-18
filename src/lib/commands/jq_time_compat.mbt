// jq date/time compatibility helpers backed by moonbitlang/x/time

///|
fn jq_time_json_to_int(value : Json) -> Int? {
  match value {
    Json::Number(n, ..) => Some(n.to_int())
    _ => None
  }
}

///|
fn jq_time_weekday_index(weekday : @time.Weekday) -> Int {
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
fn jq_time_weekday_name(weekday : @time.Weekday) -> String {
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
fn jq_time_month_name(month : Int) -> String {
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
fn jq_time_pad2(value : Int) -> String {
  if value >= 0 && value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn jq_time_plain_datetime_from_parts(
  parts : Array[Json],
) -> @time.PlainDateTime? {
  if parts.length() < 3 {
    return None
  }
  let year = match jq_time_json_to_int(parts[0]) {
    Some(value) => value
    None => return None
  }
  let month0 = match jq_time_json_to_int(parts[1]) {
    Some(value) => value
    None => return None
  }
  let day = match jq_time_json_to_int(parts[2]) {
    Some(value) => value
    None => return None
  }
  let hour = if parts.length() > 3 {
    match jq_time_json_to_int(parts[3]) {
      Some(value) => value
      None => return None
    }
  } else {
    0
  }
  let minute = if parts.length() > 4 {
    match jq_time_json_to_int(parts[4]) {
      Some(value) => value
      None => return None
    }
  } else {
    0
  }
  let second = if parts.length() > 5 {
    match jq_time_json_to_int(parts[5]) {
      Some(value) => value
      None => return None
    }
  } else {
    0
  }
  let month = month0 + 1
  let dt = try {
    Some(@time.PlainDateTime::of(year, month, day, hour~, minute~, second~))
  } catch {
    _ => None
  }
  dt
}

///|
fn jq_time_datetime_parts(dt : @time.PlainDateTime) -> Array[Json] {
  [
    jq_json_from_int(dt.year()),
    jq_json_from_int(dt.month() - 1),
    jq_json_from_int(dt.day()),
    jq_json_from_int(dt.hour()),
    jq_json_from_int(dt.minute()),
    jq_json_from_int(dt.second()),
    jq_json_from_int(jq_time_weekday_index(dt.weekday())),
    jq_json_from_int(dt.ordinal() - 1),
  ]
}

///|
fn jq_time_iso_utc_from_datetime(dt : @time.PlainDateTime) -> String {
  "\{dt.year()}-\{jq_time_pad2(dt.month())}-\{jq_time_pad2(dt.day())}T\{jq_time_pad2(dt.hour())}:\{jq_time_pad2(dt.minute())}:\{jq_time_pad2(dt.second())}Z"
}

///|
fn jq_time_long_date_from_datetime(dt : @time.PlainDateTime) -> String {
  "\{jq_time_weekday_name(dt.weekday())}, \{jq_time_month_name(dt.month())} \{jq_time_pad2(dt.day())}, \{dt.year()}"
}

///|
fn jq_time_plain_datetime_from_unix(
  second : Int64,
) -> @time.PlainDateTime? {
  let zoned = @time.unix(second, zone=@time.utc_zone) catch {
    _ => return None
  }
  Some(zoned.to_plain_date_time())
}

///|
fn jq_time_plain_datetime_from_iso_utc(
  text : String,
) -> @time.PlainDateTime? {
  if !text.has_suffix("Z") || text.length() <= 1 {
    return None
  }
  let plain = text.view(start_offset=0, end_offset=text.length() - 1).to_string()
  let dt = try {
    Some(@time.PlainDateTime::from_string(plain))
  } catch {
    _ => None
  }
  dt
}

///|
fn jq_time_unix_from_plain_datetime(
  dt : @time.PlainDateTime,
) -> Int64 {
  @time.ZonedDateTime::from_plain_datetime(dt, zone=@time.utc_zone)
  .to_unix_second()
}
