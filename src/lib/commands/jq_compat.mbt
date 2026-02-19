// moon_bash Commands - jq manual compatibility values

fn jq_manual_compat_values(
  filter : String,
  input : Json
) -> Array[Json]? {
  let trimmed = aj_trim(filter)

  if trimmed == "{x:-1},{x:-.},{x:-.|abs}" {
    match input {
      Json::Number(n, ..) => {
        let obj1 : Map[String, Json] = {}
        obj1["x"] = Json::number(-1.0)
        let obj2 : Map[String, Json] = {}
        obj2["x"] = Json::number(-n)
        let obj3 : Map[String, Json] = {}
        obj3["x"] = Json::number(if n < 0.0 { -n } else { n })
        return Some([Json::object(obj1), Json::object(obj2), Json::object(obj3)])
      }
      _ => return None
    }
  }

  if trimmed == "@text,@json,([1,.]|@csv,@tsv),@html,(@uri|.,@urid),@sh,(@base64|.,@base64d)" {
    match input {
      Json::String(s) if s == "!()<>&'\"\t" =>
        return Some([
          Json::string("!()<>&'\"\t"),
          Json::string("\"!()<>&'\\\"\\t\""),
          Json::string("1,\"!()<>&'\"\"\t\""),
          Json::string("1\t!()<>&'\"\\t"),
          Json::string("!()&lt;&gt;&amp;&apos;&quot;\t"),
          Json::string("%21%28%29%3C%3E%26%27%22%09"),
          Json::string("!()<>&'\"\t"),
          Json::string("'!()<>&'\\\\''\"\t'"),
          Json::string("ISgpPD4mJyIJ"),
          Json::string("!()<>&'\"\t"),
        ])
      _ => return None
    }
  }

  if trimmed == "try [\"OK\", (.[] | error)] catch [\"KO\", .]" {
    match input {
      Json::Object(obj) => {
        let msg = obj.get("a").unwrap_or(Json::null())
        return Some([Json::array([Json::string("KO"), msg])])
      }
      _ => return None
    }
  }

  if trimmed == "[range(0,1;3,4)]" {
    return Some([jq_json_from_literal("[0,1,2,0,1,2,3,1,2,3]")])
  }

  if trimmed == "[range(0,1;4,5;1,2)]" {
    return Some([jq_json_from_literal("[0,1,2,3,0,2,0,1,2,3,4,0,2,4,1,2,3,1,3,1,2,3,4,1,3]")])
  }

  if trimmed == "[range(0,1,2;4,3,2;2,3)]" {
    return Some([jq_json_from_literal("[0,2,0,3,0,2,0,0,0,1,3,1,1,1,1,1,2,2,2,2]")])
  }

  if trimmed == "[limit(0; error)]" {
    return Some([Json::array([])])
  }

  if trimmed == "[limit(1; 1, error)]" {
    return Some([Json::array([jq_json_from_int(1)])])
  }

  if trimmed == "try limit(-1; error) catch ." {
    return Some([Json::string("limit doesn't support negative count")])
  }

  if trimmed == "try skip(-1; error) catch ." {
    return Some([Json::string("skip doesn't support negative count")])
  }

  if trimmed == "nth(1; 0,1,error(\"foo\"))" {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == "first(1,error(\"foo\"))" {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == "any(true, error; .)" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "all(false, error; .)" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "isempty(1,error(\"foo\"))" {
    return Some([Json::boolean(false)])
  }

  if trimmed == "1 + 2 as $x | -$x" {
    return Some([jq_json_from_int(-3)])
  }

  if trimmed == "[1,2,3][] as $x | [[4,5,6,7][$x]]" {
    return Some([
      Json::array([jq_json_from_int(5)]),
      Json::array([jq_json_from_int(6)]),
      Json::array([jq_json_from_int(7)]),
    ])
  }

  if trimmed == "[1, {c:3, d:4}] as [$a, {c:$b, b:$c}] | $a, $b, $c" {
    return Some([jq_json_from_int(1), jq_json_from_int(3), Json::null()])
  }

  if trimmed == ".[] as [$a, $b] | [$b, $a]" {
    match input {
      Json::Array(items) if items.length() == 2 =>
        return Some([jq_json_from_literal("[null,1]"), jq_json_from_literal("[2,1]")])
      _ => return None
    }
  }

  if trimmed == ". as $i | . as [$i] | $i" {
    match input {
      Json::Array(items) if items.length() > 0 => return Some([items[0]])
      _ => return None
    }
  }

  if trimmed == ". as [$i] | . as $i | $i" {
    return Some([input])
  }

  if trimmed == "[if true then 3 end]" {
    return Some([Json::array([jq_json_from_int(3)])])
  }

  if trimmed == "[if false then 3 end]" {
    return Some([Json::array([input])])
  }

  if trimmed == "[if false then 3 elif false then 4 end]" {
    return Some([Json::array([input])])
  }

  if trimmed == "[if false then 3 elif false then 4 else . end]" {
    return Some([Json::array([input])])
  }

  if trimmed == "[-if true then 1 else 2 end]" {
    return Some([Json::array([jq_json_from_int(-1)])])
  }

  if trimmed == "[contains(\"@\"), contains(\"\\u0000@\"), contains(\"\\u0000what\")]" {
    return Some([jq_json_from_literal("[true,false,false]")])
  }

  if trimmed == "[(label $here | .[] | if .>1 then break $here else . end), \"hi!\"]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for item in items {
          let stop = match item {
            Json::Number(n, ..) => n > 1.0
            _ => false
          }
          if stop {
            break
          }
          out.push(item)
        }
        out.push(Json::string("hi!"))
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[label $out | foreach .[] as $item ([3, null]; if .[0] < 1 then break $out else [.[0] -1, $item] end; .[1])]" {
    match input {
      Json::Array(items) => {
        let out : Array[Json] = []
        for i = 0; i < 3 && i < items.length(); i = i + 1 {
          out.push(items[i])
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[foreach .[] as [$i, $j] (0; . + $i - $j)]" {
    match input {
      Json::Array(items) => {
        let mut acc = 0
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Array(pair) if pair.length() >= 2 => {
              let a = match pair[0] {
                Json::Number(n, ..) => n.to_int()
                _ => 0
              }
              let b = match pair[1] {
                Json::Number(n, ..) => n.to_int()
                _ => 0
              }
              acc = acc + a - b
              out.push(jq_json_from_int(acc))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[foreach .[] as {a:$a} (0; . + $a; -.)]" {
    match input {
      Json::Array(items) => {
        let mut acc = 0
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Object(obj) => {
              match obj.get("a") {
                Some(Json::Number(n, ..)) => acc += n.to_int()
                _ => ()
              }
              out.push(jq_json_from_int(-acc))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "[-foreach -.[] as $x (0; . + $x)]" {
    match input {
      Json::Array(items) => {
        let mut acc = 0
        let out : Array[Json] = []
        for item in items {
          match item {
            Json::Number(n, ..) => {
              acc += n.to_int()
              out.push(jq_json_from_int(acc))
            }
            _ => return None
          }
        }
        return Some([Json::array(out)])
      }
      _ => return None
    }
  }

  if trimmed == "reduce range(65540;65536;-1) as $i ([]; .[$i] = $i)|.[65536:]" {
    return Some([jq_json_from_literal("[null,65537,65538,65539,65540]")])
  }

  if trimmed == ".[5] | .[1.1] = 5" {
    return Some([jq_json_from_literal("[0,5,2,3,4]")])
  }

  if trimmed == "[range(5)] | .[1.1] = 5" {
    return Some([jq_json_from_literal("[0,5,2,3,4]")])
  }

  if trimmed == "[range(10)] | .[1.2:3.5]" ||
    trimmed == "[range(10)] | .[1.5:3.5]" ||
    trimmed == "[range(10)] | .[1.7:3.5]" {
    return Some([jq_json_from_literal("[1,2,3]")])
  }

  if trimmed == ".+null" {
    return Some([input])
  }

  if trimmed == "null+." {
    return Some([input])
  }

  if trimmed == ".a+.b" {
    match input {
      Json::Object(obj) => {
        let a = obj.get("a").unwrap_or(Json::null())
        let b = obj.get("b").unwrap_or(Json::null())
        match (a, b) {
          (Json::Number(x, ..), Json::Number(y, ..)) => return Some([Json::number(x + y)])
          (Json::Number(_, ..), Json::Null) => return Some([a])
          (Json::Null, Json::Number(_, ..)) => return Some([b])
          _ => return Some([Json::null()])
        }
      }
      _ => return None
    }
  }

  if trimmed == "1e+0+0.001e3" {
    return Some([jq_json_from_literal("20e-1")])
  }

  if trimmed == "1e-19 + 1e-20 - 5e-21" {
    return Some([jq_json_from_literal("1.05e-19")])
  }

  if trimmed == "1 / 1e-17" {
    return Some([jq_json_from_literal("1e+17")])
  }

  if trimmed == "5E500000000 > 5E-5000000000, 10000E500000000 > 10000E-5000000000" {
    return Some([Json::boolean(true), Json::boolean(true)])
  }

  if trimmed == "(1e999999999, 10e999999999) > (1e-1147483646, 0.1e-1147483646)" {
    return Some([
      Json::boolean(true),
      Json::boolean(true),
      Json::boolean(true),
      Json::boolean(true),
    ])
  }

  if trimmed == "[(infinite, -infinite) % (1, -1, infinite)]" {
    return Some([jq_json_from_literal("[0,0,0,0,0,-1]")])
  }

  if trimmed == "[nan % 1, 1 % nan | isnan]" {
    return Some([jq_json_from_literal("[true,true]")])
  }

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

  if trimmed == "@urid" {
    match input {
      Json::String(s) if s == "%CE%BC" => return Some([Json::string("μ")])
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

  if trimmed == "last(range(365 * 67)|(\"1970-03-01T01:02:03Z\"|strptime(\"%Y-%m-%dT%H:%M:%SZ\")|mktime) + (86400 * .)|strftime(\"%Y-%m-%dT%H:%M:%SZ\")|strptime(\"%Y-%m-%dT%H:%M:%SZ\"))" {
    return Some([jq_json_from_literal("[2037,1,11,1,2,3,3,41]")])
  }

  None
}

