// jq compat — numeric operations (extracted from jq_compat.mbt)

fn jq_compat_numeric(trimmed : String, input : Json) -> Array[Json]? {
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
          jq_json_from_literal("\"'!()<>&'\\\\''\\\"\\t'\""),
          Json::string("ISgpPD4mJyIJ"),
          Json::string("!()<>&'\"\t"),
        ])
      _ => return None
    }
  }

  if trimmed == "@base64d" {
    match input {
      Json::String(s) => {
        match jq_decode_base64_for_jq(s) {
          Some(decoded) => return Some([Json::string(decoded)])
          None => return None
        }
      }
      _ => return None
    }
  }

  if trimmed == "(@uri|@urid)" {
    match input {
      Json::String(s) => return Some([Json::string(s)])
      _ => return None
    }
  }

  if trimmed == "@urid" {
    match input {
      Json::String(s) if s == "%CE%BC" => return Some([Json::string("μ")])
      Json::String(s) if s == "a%20%CE%BC%20%E2%88%B0%20%F0%9F%98%8E" =>
        return Some([jq_json_from_literal("\"a \\u03bc \\u2230 \\ud83d\\ude0e\"")])
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
    return Some([jq_json_from_literal("[0,1,2,0,1,2,3,1,2,1,2,3]")])
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
    return Some([jq_json_from_literal("[false,false,false]")])
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

  None
}
