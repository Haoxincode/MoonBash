// moon_bash Commands - jq helper utilities

fn jq_strip_bom(text : String) -> String {
  if text.length() > 0 && text[0].to_int() == 65279 {
    aj_substr(text, 1, text.length())
  } else {
    text
  }
}

fn jq_json_from_int(n : Int) -> Json {
  try {
    @json.parse(n.to_string()[:])
  } catch {
    _ => Json::null()
  }
}

fn jq_json_from_literal(literal : String) -> Json {
  try {
    @json.parse(literal[:])
  } catch {
    _ => Json::null()
  }
}

fn jq_trimstr_once(input : String, trim : String) -> String {
  if trim.length() == 0 {
    return input
  }
  let mut out = input
  if aj_starts_with(out, trim) {
    out = aj_substr(out, trim.length(), out.length())
  }
  if aj_ends_with(out, trim) {
    out = aj_substr(out, 0, out.length() - trim.length())
  }
  out
}

fn jq_is_trim_ws_unit(code : Int) -> Bool {
  code == 9 ||
  code == 10 ||
  code == 11 ||
  code == 12 ||
  code == 13 ||
  code == 32 ||
  code == 133 ||
  code == 160 ||
  code == 5760 ||
  (code >= 8192 && code <= 8202) ||
  code == 8232 ||
  code == 8233 ||
  code == 8239 ||
  code == 8287 ||
  code == 12288
}

fn jq_ltrim_unicode(input : String) -> String {
  let mut start = 0
  while start < input.length() {
    if jq_is_trim_ws_unit(input[start].to_int()) {
      start += 1
    } else {
      break
    }
  }
  if start == 0 {
    input
  } else {
    aj_substr(input, start, input.length())
  }
}

fn jq_rtrim_unicode(input : String) -> String {
  let mut end_ = input.length()
  while end_ > 0 {
    if jq_is_trim_ws_unit(input[end_ - 1].to_int()) {
      end_ -= 1
    } else {
      break
    }
  }
  if end_ == input.length() {
    input
  } else {
    aj_substr(input, 0, end_)
  }
}

fn jq_trim_unicode(input : String) -> String {
  jq_rtrim_unicode(jq_ltrim_unicode(input))
}

fn jq_manual_trim_map(input : Json, mode : String) -> Json? {
  match input {
    Json::Array(items) => {
      let out : Array[Json] = []
      for item in items {
        match item {
          Json::String(s) => {
            let normalized = if mode == "trim" {
              jq_trim_unicode(s)
            } else if mode == "ltrim" {
              jq_ltrim_unicode(s)
            } else {
              jq_rtrim_unicode(s)
            }
            out.push(Json::string(normalized))
          }
          _ => return None
        }
      }
      Some(Json::array(out))
    }
    _ => None
  }
}

fn jq_extract_object_number(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

fn jq_bsearch_numbers(haystack : Array[Int], needle : Int) -> Int {
  let mut low = 0
  let mut high = haystack.length()
  while low < high {
    let mid = (low + high) / 2
    let value = haystack[mid]
    if value == needle {
      return mid
    }
    if value < needle {
      low = mid + 1
    } else {
      high = mid
    }
  }
  -(low + 1)
}

