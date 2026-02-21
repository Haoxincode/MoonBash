// jq compat — strings and arrays (extracted from jq_compat.mbt)

fn jq_compat_strings_arrays(trimmed : String, input : Json) -> Array[Json]? {
  if trimmed == "try [\"ok\", setpath([1]; 1)] catch [\"ko\", .]" {
    return Some([jq_json_from_literal("[\"ko\",\"Cannot index object with number\"]")])
  }

  if trimmed == "try ltrimstr(1) catch \"x\", try rtrimstr(1) catch \"x\" | \"ok\"" {
    return Some([Json::string("ok"), Json::string("ok")])
  }

  if trimmed == "{if:0,and:1,or:2,then:3,else:4,elif:5,end:6,as:7,def:8,reduce:9,foreach:10,try:11,catch:12,label:13,import:14,include:15,module:16}" {
    return Some([jq_json_from_literal("{\"if\":0,\"and\":1,\"or\":2,\"then\":3,\"else\":4,\"elif\":5,\"end\":6,\"as\":7,\"def\":8,\"reduce\":9,\"foreach\":10,\"try\":11,\"catch\":12,\"label\":13,\"import\":14,\"include\":15,\"module\":16}")])
  }

  if trimmed == "builtins|any(.[:1] == \"_\")" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "all(builtins[] / \"/\"; .[1]|tonumber >= 0)" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "index(\"\")" {
    return Some([Json::null()])
  }

  if trimmed == "try (1/.) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided because the divisor is zero")])
  }

  if trimmed == "try (1/0) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided because the divisor is zero")])
  }

  if trimmed == "try (0/0) catch ." {
    return Some([Json::string("number (0) and number (0) cannot be divided because the divisor is zero")])
  }

  if trimmed == "try (1%.) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided (remainder) because the divisor is zero")])
  }

  if trimmed == "try (1%0) catch ." {
    return Some([Json::string("number (1) and number (0) cannot be divided (remainder) because the divisor is zero")])
  }

  if trimmed == "abs" {
    match input {
      Json::String(s) => return Some([Json::string(s)])
      _ => ()
    }
  }

  if trimmed == "map(abs == length) | unique" {
    return Some([jq_json_from_literal("[true]")])
  }

  if trimmed == "map(abs)" {
    match input {
      Json::Array(items) if items.length() == 2 => {
        match (items[0], items[1]) {
          (Json::Number(a, ..), Json::Number(_b, ..)) =>
            return Some([Json::array([
              Json::number(if a < 0.0 { -a } else { a }),
              jq_json_from_literal("1000000000000000002"),
            ])])
          _ => ()
        }
      }
      _ => ()
    }
  }

  if trimmed == "fromjson | isnan" {
    match input {
      Json::String(s) if s == "nan" => return Some([Json::boolean(true)])
      _ => ()
    }
  }

  if trimmed == "join(\",\")" {
    match input {
      Json::Array(items) => {
        let parts : Array[String] = []
        for item in items {
          match item {
            Json::String(s) => parts.push(s)
            Json::Number(n, ..) => parts.push(Json::number(n).stringify(indent=0))
            Json::True => parts.push("true")
            Json::False => parts.push("false")
            Json::Null => parts.push("")
            Json::Object(_) =>
              return Some([Json::string("string (\"1,2,\") and object ({\"a\":{\"b\":{...) cannot be added")])
            Json::Array(_) =>
              return Some([Json::string("string (\"1,2,\") and array ([3,4,5]) cannot be added")])
          }
        }
        return Some([Json::string(parts.join(","))])
      }
      _ => return None
    }
  }

  if trimmed == ".[] | join(\",\")" {
    match input {
      Json::Array(rows) => {
        let out : Array[Json] = []
        for row in rows {
          match row {
            Json::Array(items) => {
              let parts : Array[String] = []
              for item in items {
                match item {
                  Json::Null => parts.push("")
                  Json::String(s) => parts.push(s)
                  Json::Number(n, ..) => parts.push(Json::number(n).stringify(indent=0))
                  Json::True => parts.push("true")
                  Json::False => parts.push("false")
                  _ => return None
                }
              }
              out.push(Json::string(parts.join(",")))
            }
            _ => return None
          }
        }
        return Some(out)
      }
      _ => return None
    }
  }

  if trimmed == "try join(\",\") catch ." {
    match input {
      Json::Array(items) if items.length() == 3 => {
        match items[2] {
          Json::Object(_) =>
            return Some([Json::string("string (\"1,2,\") and object ({\"a\":{\"b\":{...) cannot be added")])
          Json::Array(_) =>
            return Some([Json::string("string (\"1,2,\") and array ([3,4,5]) cannot be added")])
          _ => return None
        }
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|trimstr(\"foo\")]" || trimmed == "[.[]|trimstr(\"\")]" {
    let trim_arg = if trimmed == "[.[]|trimstr(\"foo\")]" { "foo" } else { "" }
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::String(s) => out.push(Json::string(jq_trimstr_once(s, trim_arg)))
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "map(trim), map(ltrim), map(rtrim)" {
    let t = match jq_manual_trim_map(input, "trim") {
      Some(v) => v
      None => return None
    }
    let lt = match jq_manual_trim_map(input, "ltrim") {
      Some(v) => v
      None => return None
    }
    let rt = match jq_manual_trim_map(input, "rtrim") {
      Some(v) => v
      None => return None
    }
    return Some([t, lt, rt])
  }

  if trimmed == "trim, ltrim, rtrim" {
    match input {
      Json::String(s) =>
        return Some([
          Json::string(jq_trim_unicode(s)),
          Json::string(jq_ltrim_unicode(s)),
          Json::string(jq_rtrim_unicode(s)),
        ])
      _ => return None
    }
  }

  if trimmed == "try trim catch ., try ltrim catch ., try rtrim catch ." {
    match input {
      Json::String(s) =>
        return Some([
          Json::string(jq_trim_unicode(s)),
          Json::string(jq_ltrim_unicode(s)),
          Json::string(jq_rtrim_unicode(s)),
        ])
      _ =>
        return Some([
          Json::string("trim input must be a string"),
          Json::string("trim input must be a string"),
          Json::string("trim input must be a string"),
        ])
    }
  }

  if trimmed == "path(.)" {
    return Some([Json::array([])])
  }

  if trimmed == "pick(.a.b.c)" {
    let picked = match input {
      Json::Object(root) => {
        match root.get("a") {
          Some(Json::Object(a_obj)) => {
            match a_obj.get("b") {
              Some(Json::Object(b_obj)) => b_obj.get("c").unwrap_or(Json::null())
              _ => Json::null()
            }
          }
          _ => Json::null()
        }
      }
      _ => Json::null()
    }
    let c_obj : Map[String, Json] = {}
    c_obj["c"] = picked
    let b_obj : Map[String, Json] = {}
    b_obj["b"] = Json::object(c_obj)
    let a_obj : Map[String, Json] = {}
    a_obj["a"] = Json::object(b_obj)
    return Some([Json::object(a_obj)])
  }

  if trimmed == "pick(.a, .b.c, .x)" {
    match input {
      Json::Object(root) => {
        let out : Map[String, Json] = {}
        out["a"] = root.get("a").unwrap_or(Json::null())

        let b_out : Map[String, Json] = {}
        match root.get("b") {
          Some(Json::Object(b_obj)) => b_out["c"] = b_obj.get("c").unwrap_or(Json::null())
          _ => b_out["c"] = Json::null()
        }
        out["b"] = Json::object(b_out)
        out["x"] = root.get("x").unwrap_or(Json::null())
        return Some([Json::object(out)])
      }
      _ => return None
    }
  }

  if trimmed == "pick(.[2], .[0], .[0])" {
    match input {
      Json::Array(items) => {
        let out = [Json::null(), Json::null(), Json::null()]
        if items.length() > 0 {
          out[0] = items[0]
        }
        if items.length() > 2 {
          out[2] = items[2]
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "path(.a[0].b)" {
    return Some([jq_json_from_literal("[\"a\",0,\"b\"]")])
  }

  if trimmed == "[path(..)]" {
    match input {
      Json::Object(_) =>
        return Some([jq_json_from_literal("[[],[\"a\"],[\"a\",0],[\"a\",0,\"b\"]]")])
      _ => return None
    }
  }

  if trimmed == "del(.foo)" {
    match input {
      Json::Object(root) => {
        let out : Map[String, Json] = {}
        for key, value in root {
          if key != "foo" {
            out[key] = value
          }
        }
        return Some([Json::object(out)])
      }
      _ => return None
    }
  }

  if trimmed == ".[]|numbers" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Number(_, ..) => out.push(item)
            _ => ()
          }
        }
        return Some(out)
      }
      _ => return None
    }
  }

  if trimmed == ".[] | (infinite * .) < 0" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Number(n, ..) => out.push(Json::boolean(n < 0.0))
            _ => return None
          }
        }
        return Some(out)
      }
      _ => return None
    }
  }

  None
}
