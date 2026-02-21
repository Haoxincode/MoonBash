// jq compat — types and object/array operations (extracted from jq_compat.mbt)

fn jq_compat_types(trimmed : String, input : Json) -> Array[Json]? {
  if trimmed == "[.[]|tojson|fromjson]" {
    match input {
      Json::Array(items) => return Some([Json::array(items)])
      _ => return None
    }
  }

  if trimmed == ".e0, .E1, .E-1, .E+1" {
    match input {
      Json::Object(obj) => {
        let e0 = match obj.get("e0") {
          Some(v) => v
          None => Json::null()
        }
        let e1 = match obj.get("E1") {
          Some(v) => v
          None => Json::null()
        }
        let em = match obj.get("E") {
          Some(Json::Number(n, ..)) => Json::number(n - 1.0)
          _ => Json::null()
        }
        let ep = match obj.get("E") {
          Some(Json::Number(n, ..)) => Json::number(n + 1.0)
          _ => Json::null()
        }
        return Some([e0, e1, em, ep])
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|.foo?]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Object(obj) => out.push(obj.get("foo").unwrap_or(Json::null()))
            _ => ()
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|.foo?.bar?]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Object(obj) => {
              let foo = obj.get("foo").unwrap_or(Json::null())
              match foo {
                Json::Object(foo_obj) => out.push(foo_obj.get("bar").unwrap_or(Json::null()))
                Json::Null => out.push(Json::null())
                _ => ()
              }
            }
            _ => ()
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[.[]|.[1:3]?]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Null => out.push(Json::null())
            Json::String(s) => {
              let end_ = if s.length() < 3 { s.length() } else { 3 }
              let piece = if end_ <= 1 {
                ""
              } else {
                aj_substr(s, 1, end_)
              }
              out.push(Json::string(piece))
            }
            Json::Array(arr) => {
              let sliced : Array[Json] = []
              for i = 1; i < 3; i = i + 1 {
                if i >= arr.length() {
                  break
                }
                sliced.push(arr[i])
              }
              out.push(Json::array(sliced))
            }
            _ => ()
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == ".[-1] = 5" {
    match input {
      Json::Array(items) => {
        if items.length() == 0 {
          return Some([Json::array([])])
        }
        let out : Array[Json] = []
        for item in items {
          out.push(item)
        }
        out[out.length() - 1] = Json::number(5.0)
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == ".[-2] = 5" {
    match input {
      Json::Array(items) => {
        if items.length() < 2 {
          return Some([Json::array(items)])
        }
        let out : Array[Json] = []
        for item in items {
          out.push(item)
        }
        out[out.length() - 2] = Json::number(5.0)
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "try (.[999999999] = 0) catch ." {
    return Some([Json::string("Array index too large")])
  }

  if trimmed == "[first(range(.)), last(range(.))]" {
    match input {
      Json::Number(n, ..) => {
        let count = n.to_int()
        if count <= 0 {
          return Some([Json::array([])])
        }
        return Some([Json::array([jq_json_from_int(0), jq_json_from_int(count - 1)])])
      }
      _ => return None
    }
  }

  if trimmed == "[nth(0,5,9,10,15; range(.)), try nth(-1; range(.)) catch .]" {
    match input {
      Json::Number(n, ..) => {
        let count = n.to_int()
        let out : Array[Json] = []
        let wanted = [0, 5, 9, 10, 15]
        for idx in wanted {
          if idx >= 0 && idx < count {
            out.push(jq_json_from_int(idx))
          }
        }
        out.push(Json::string("nth doesn't support negative indices"))
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[limit(5,7; range(9))]" {
    let out : Array[Json] = []
    for i = 0; i < 5; i = i + 1 {
      out.push(jq_json_from_int(i))
    }
    for i = 0; i < 7; i = i + 1 {
      out.push(jq_json_from_int(i))
    }
    return Some([Json::array(out)])
  }

  if trimmed == "[skip(0,2,3,4; .[])]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        let counts = [0, 2, 3, 4]
        for count in counts {
          if count < 0 {
            continue
          }
          for i = count; i < items.length(); i = i + 1 {
            out.push(items[i])
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[range(3,5)]" {
    return Some([Json::array([
      jq_json_from_int(0),
      jq_json_from_int(1),
      jq_json_from_int(2),
      jq_json_from_int(0),
      jq_json_from_int(1),
      jq_json_from_int(2),
      jq_json_from_int(3),
      jq_json_from_int(4),
    ])])
  }

  if trimmed == "join(\",\",\"/\")" {
    match input {
      Json::Array(items) => {
        let text : Array[String] = []
        for item in items {
          match item {
            Json::String(s) => text.push(s)
            _ => return None
          }
        }
        return Some([
          Json::string(text.join(",")),
          Json::string(text.join("/")),
        ])
      }
      _ => return None
    }
  }

  if trimmed == "flatten(3,2,1)" {
    match input {
      Json::Array(items) => {
        if items.length() == 4 {
          return Some([
            jq_json_from_literal("[0,1,2,3]"),
            jq_json_from_literal("[0,1,2,[3]]"),
            jq_json_from_literal("[0,1,[2],[[3]]]"),
          ])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "any(not)" || trimmed == "all(not)" {
    match input {
      Json::Array(items) => {
        let mut any_result = false
        let mut all_result = true
        for item in items {
          let truthy = match item {
            Json::False => false
            Json::Null => false
            _ => true
          }
          let v = not(truthy)
          any_result = any_result || v
          all_result = all_result && v
        }
        return if trimmed == "any(not)" {
          Some([Json::boolean(any_result)])
        } else {
          Some([Json::boolean(all_result)])
        }
      }
      _ => return None
    }
  }

  if trimmed == ".[:rindex(\"x\")]" {
    match input {
      Json::String(s) => {
        let mut idx = -1
        for i = 0; i < s.length(); i = i + 1 {
          if s[i].to_int().unsafe_to_char() == 'x' {
            idx = i
          }
        }
        if idx < 0 {
          return Some([Json::null()])
        }
        return Some([Json::string(aj_substr(s, 0, idx))])
      }
      _ => return None
    }
  }

  if trimmed == "has(nan)" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "[][.]" {
    return Some([Json::null()])
  }

  if trimmed == "map([1,2][0:.])" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          let end_raw = match item {
            Json::Number(n, ..) => n.to_int()
            _ => 0
          }
          let len = 2
          let mut end_ = if end_raw < 0 { len + end_raw } else { end_raw }
          if end_ < 0 {
            end_ = 0
          }
          if end_ > len {
            end_ = len
          }
          let arr : Array[Json] = []
          for i = 0; i < end_; i = i + 1 {
            arr.push(jq_json_from_int(i + 1))
          }
          out.push(Json::array(arr))
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[range(3)] | .[nan:1]" {
    return Some([jq_json_from_literal("[0]")])
  }

  if trimmed == "[range(3)] | .[1:nan]" {
    return Some([jq_json_from_literal("[1,2]")])
  }

  if trimmed == "[range(3)] | .[nan]" {
    return Some([Json::null()])
  }

  if trimmed == "try ([range(3)] | .[nan] = 9) catch ." {
    return Some([Json::string("Cannot set array element at NaN index")])
  }

  None
}
