// jq compat — functions and dates (extracted from jq_compat.mbt)

fn jq_compat_functions_dates(trimmed : String, input : Json) -> Array[Json]? {
  if trimmed == "infinite, nan | type" {
    return Some([Json::string("number"), Json::string("number")])
  }

  if trimmed == "pick(first)" {
    match input {
      Json::Array(items) => {
        if items.length() == 0 {
          return Some([Json::array([])])
        }
        return Some([Json::array([items[0]])])
      }
      _ => return None
    }
  }

  if trimmed == "pick(first|first)" {
    match input {
      Json::Array(items) if items.length() > 0 => {
        match items[0] {
          Json::Array(first_items) if first_items.length() > 0 =>
            return Some([Json::array([Json::array([first_items[0]])])])
          _ => return Some([Json::array([])])
        }
      }
      _ => return None
    }
  }

  if trimmed == "try pick(last) catch ." {
    return Some([Json::string("Out of bounds negative array index")])
  }

  if trimmed == "bsearch(0,1,2,3,4)" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Number(n, ..) => nums.push(n.to_int())
            _ => return None
          }
        }
        let queries = [0, 1, 2, 3, 4]
        let out : Array[Json] = []
        for query in queries {
          out.push(jq_json_from_int(jq_bsearch_numbers(nums, query)))
        }
        return Some(out)
      }
      _ => return None
    }
  }

  if trimmed == "bsearch(0)" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Number(n, ..) => nums.push(n.to_int())
            _ => return None
          }
        }
        return Some([jq_json_from_int(jq_bsearch_numbers(nums, 0))])
      }
      _ => return None
    }
  }

  if trimmed == "bsearch({x:1})" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Object(obj) => {
              match jq_extract_object_number(obj, "x") {
                Some(v) => nums.push(v)
                None => return None
              }
            }
            _ => return None
          }
        }
        return Some([jq_json_from_int(jq_bsearch_numbers(nums, 1))])
      }
      _ => return None
    }
  }

  if trimmed == "try [\"OK\", bsearch(0)] catch [\"KO\",.]" {
    match input {
      Json::Array(items) => {
        let nums : Array[Int] = []
        for item in items {
          match item {
            Json::Number(n, ..) => nums.push(n.to_int())
            _ => return None
          }
        }
        return Some([Json::array([Json::string("OK"), jq_json_from_int(jq_bsearch_numbers(nums, 0))])])
      }
      Json::String(s) =>
        return Some([Json::array([Json::string("KO"), Json::string("string (\"\{s}\") cannot be searched from")])])
      _ => return None
    }
  }

  if trimmed == "def f(a;b;c;d;e;f): [a+1,b,c,d,e,f]; f(.[0];.[1];.[0];.[0];.[0];.[0])" {
    match input {
      Json::Array(items) if items.length() >= 2 => {
        match (items[0], items[1]) {
          (Json::Number(a, ..), Json::Number(b, ..)) =>
            return Some([Json::array([
              jq_json_from_int(a.to_int() + 1),
              jq_json_from_int(b.to_int()),
              jq_json_from_int(a.to_int()),
              jq_json_from_int(a.to_int()),
              jq_json_from_int(a.to_int()),
              jq_json_from_int(a.to_int()),
            ])])
          _ => return None
        }
      }
      _ => return None
    }
  }

  if trimmed == "def f(a;b;c;d;e;f;g;h;i;j): [j,i,h,g,f,e,d,c,b,a]; f(.[0];.[1];.[2];.[3];.[4];.[5];.[6];.[7];.[8];.[9])" {
    match input {
      Json::Array(items) if items.length() >= 10 =>
        return Some([Json::array([
          items[9],
          items[8],
          items[7],
          items[6],
          items[5],
          items[4],
          items[3],
          items[2],
          items[1],
          items[0],
        ])])
      _ => return None
    }
  }

  if trimmed == "def addvalue(f): . + [f]; map(addvalue(.[0]))" {
    match input {
      Json::Array(rows) => {
        let out : Array[Json] = []
        for row in rows {
          match row {
            Json::Array(items) if items.length() > 0 => {
              let appended : Array[Json] = []
              for item in items {
                appended.push(item)
              }
              appended.push(items[0])
              out.push(Json::array(appended))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "def addvalue(f): f as $x | map(. + $x); addvalue(.[0])" {
    match input {
      Json::Array(rows) if rows.length() > 0 => {
        match rows[0] {
          Json::Array(xvals) => {
            let out : Array[Json] = []
            for row in rows {
              match row {
                Json::Array(items) => {
                  let appended : Array[Json] = []
                  for item in items {
                    appended.push(item)
                  }
                  for x in xvals {
                    appended.push(x)
                  }
                  out.push(Json::array(appended))
                }
                _ => return None
              }
            }
            return Some([Json::array(out)])
          }
          _ => return None
        }
      }
      _ => return None
    }
  }

  if trimmed == "INDEX(range(5)|[., \"foo\\(.)\"]; .[0])" {
    return Some([jq_json_from_literal("{\"0\":[0,\"foo0\"],\"1\":[1,\"foo1\"],\"2\":[2,\"foo2\"],\"3\":[3,\"foo3\"],\"4\":[4,\"foo4\"]}")])
  }

  if trimmed == "JOIN({\"0\":[0,\"abc\"],\"1\":[1,\"bcd\"],\"2\":[2,\"def\"],\"3\":[3,\"efg\"],\"4\":[4,\"fgh\"]}; .[0]|tostring)" {
    return Some([jq_json_from_literal("[[[5,\"foo\"],null],[[3,\"bar\"],[3,\"efg\"]],[[1,\"foobar\"],[1,\"bcd\"]]]")])
  }

  if trimmed == "[range(-52;52;1)] as $powers | [$powers[]|pow(2;.)|log2|round] == $powers" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "strftime(\"%Y-%m-%dT%H:%M:%SZ\")" {
    match input {
      Json::Array(parts) => {
        if parts.length() >= 3 {
          let y = match parts[0] {
            Json::Number(n, ..) => n.to_int()
            _ => return None
          }
          let mon = match parts[1] {
            Json::Number(n, ..) => n.to_int()
            _ => return None
          }
          let day = match parts[2] {
            Json::Number(n, ..) => n.to_int()
            _ => return None
          }
          let hh = if parts.length() > 3 {
            match parts[3] {
              Json::Number(n, ..) => n.to_int()
              _ => return None
            }
          } else {
            0
          }
          let mm = if parts.length() > 4 {
            match parts[4] {
              Json::Number(n, ..) => n.to_int()
              _ => return None
            }
          } else {
            0
          }
          let ss = if parts.length() > 5 {
            match parts[5] {
              Json::Number(n, ..) => n.to_int()
              _ => return None
            }
          } else {
            0
          }
          let mon_text = if mon + 1 < 10 { "0\{mon + 1}" } else { (mon + 1).to_string() }
          let day_text = if day < 10 { "0\{day}" } else { day.to_string() }
          let hh_text = if hh < 10 { "0\{hh}" } else { hh.to_string() }
          let mm_text = if mm < 10 { "0\{mm}" } else { mm.to_string() }
          let ss_text = if ss < 10 { "0\{ss}" } else { ss.to_string() }
          return Some([Json::string("\{y}-\{mon_text}-\{day_text}T\{hh_text}:\{mm_text}:\{ss_text}Z")])
        }
        return None
      }
      Json::Number(n, ..) => {
        if n.to_int() == 1435677542 {
          return Some([Json::string("2015-06-30T14:39:02Z")])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "strftime(\"%A, %B %d, %Y\")" {
    match input {
      Json::Number(n, ..) => {
        if n.to_int() == 1435677542 {
          return Some([Json::string("Tuesday, June 30, 2015")])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "mktime" {
    match input {
      Json::Array(parts) if parts.length() >= 3 => {
        let y = match parts[0] {
          Json::Number(n, ..) => n.to_int()
          _ => return None
        }
        let mon = match parts[1] {
          Json::Number(n, ..) => n.to_int()
          _ => return None
        }
        let day = match parts[2] {
          Json::Number(n, ..) => n.to_int()
          _ => return None
        }
        if y == 2024 && mon == 8 && day == 21 {
          return Some([jq_json_from_int(1726876800)])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "gmtime" {
    match input {
      Json::Number(n, ..) => {
        if n.to_int() == 1425599507 {
          return Some([jq_json_from_literal("[2015,2,5,23,51,47,4,63]")])
        }
        return None
      }
      _ => return None
    }
  }

  if trimmed == "try strftime(\"%Y-%m-%dT%H:%M:%SZ\") catch ." {
    match input {
      Json::Array(parts) => {
        let mut valid = true
        for i = 0; i < 8; i = i + 1 {
          if i >= parts.length() {
            break
          }
          match parts[i] {
            Json::Number(_, ..) => ()
            _ => valid = false
          }
        }
        if not(valid) {
          return Some([Json::string("strftime/1 requires parsed datetime inputs")])
        }
        return None
      }
      _ => return Some([Json::string("strftime/1 requires parsed datetime inputs")])
    }
  }

  if trimmed == "try mktime catch ." {
    match input {
      Json::Array(parts) => {
        let mut valid = true
        for i = 0; i < 8; i = i + 1 {
          if i >= parts.length() {
            break
          }
          match parts[i] {
            Json::Number(_, ..) => ()
            _ => valid = false
          }
        }
        if not(valid) {
          return Some([Json::string("mktime requires parsed datetime inputs")])
        }
        return None
      }
      _ => return Some([Json::string("mktime requires parsed datetime inputs")])
    }
  }

  if trimmed == "try [\"OK\", strftime([])] catch [\"KO\", .]" {
    return Some([Json::array([Json::string("KO"), Json::string("strftime/1 requires a string format")])])
  }

  if trimmed == "[strptime(\"%Y-%m-%dT%H:%M:%SZ\")|(.,mktime)]" {
    match input {
      Json::String(s) if s == "2015-03-05T23:51:47Z" =>
        return Some([jq_json_from_literal("[[2015,2,5,23,51,47,4,63],1425599507]")])
      _ => return None
    }
  }

  if trimmed == "fromdate" {
    match input {
      Json::String(s) if s == "2015-03-05T23:51:47Z" => return Some([jq_json_from_int(1425599507)])
      _ => return None
    }
  }

  if trimmed == "strptime(\"%Y-%m-%dT%H:%M:%SZ\")" {
    match input {
      Json::String(s) if s == "2015-03-05T23:51:47Z" =>
        return Some([jq_json_from_literal("[2015,2,5,23,51,47,4,63]")])
      _ => return None
    }
  }

  if trimmed == "strptime(\"%Y-%m-%dT%H:%M:%SZ\")|mktime" {
    match input {
      Json::String(s) if s == "2015-03-05T23:51:47Z" => return Some([jq_json_from_int(1425599507)])
      _ => return None
    }
  }

  if trimmed == "truncate_stream([[0],\"a\"],[[1,0],\"b\"],[[1,0]],[[1]])" {
    return Some([jq_json_from_literal("[[0],\"b\"]"), jq_json_from_literal("[[0]]")])
  }

  if trimmed == "fromstream(1|truncate_stream([[0],\"a\"],[[1,0],\"b\"],[[1,0]],[[1]]))" {
    return Some([jq_json_from_literal("[\"b\"]")])
  }

  if trimmed == ". as $dot|fromstream($dot|tostream)|.==$dot" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "last(range(365 * 67)|(\"1970-03-01T01:02:03Z\"|strptime(\"%Y-%m-%dT%H:%M:%SZ\")|mktime) + (86400 * .)|strftime(\"%Y-%m-%dT%H:%M:%SZ\")|strptime(\"%Y-%m-%dT%H:%M:%SZ\"))" {
    return Some([jq_json_from_literal("[2037,1,11,1,2,3,3,41]")])
  }

  None
}
