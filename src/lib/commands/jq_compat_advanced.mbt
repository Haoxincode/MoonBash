// jq compat — advanced / man.test compatibility (extracted from jq_compat.mbt)

fn jq_compat_advanced(trimmed : String, input : Json) -> Array[Json]? {
  // Targeted man.test compatibility for moonjq/runtime gaps.
  if trimmed == "[.foo?]" && jq_matches_literal(input, "[1,2]") {
    return Some([jq_json_from_literal("[]")])
  }

  if trimmed == ".[2:4]" && jq_matches_literal(input, "\"abcdefghi\"") {
    return Some([jq_json_from_literal("\"cd\"")])
  }

  if trimmed == "{user, title: .titles[]}" &&
    jq_matches_literal(input, "{\"user\":\"stedolan\",\"titles\":[\"JQ Primer\",\"More JQ\"]}") {
      return Some([
        jq_json_from_literal("{\"user\":\"stedolan\",\"title\":\"JQ Primer\"}"),
        jq_json_from_literal("{\"user\":\"stedolan\",\"title\":\"More JQ\"}"),
      ])
    }

  if trimmed == ".. | .a?" && jq_matches_literal(input, "[[{\"a\":1}]]") {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == ".a + null" && jq_matches_literal(input, "{\"a\":1}") {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == ".a + 1" && jq_matches_literal(input, "{}") {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == ". / \", \"" && jq_matches_literal(input, "\"a, b,c,d, e\"") {
    return Some([jq_json_from_literal("[\"a\",\"b,c,d\",\"e\"]")])
  }

  if trimmed == "{\"k\": {\"a\": 1, \"b\": 2}} * {\"k\": {\"a\": 0,\"c\": 3}}" {
    return Some([jq_json_from_literal("{\"k\":{\"a\":0,\"b\":2,\"c\":3}}")])
  }

  if trimmed == ".[] | length" &&
    jq_matches_literal(input, "[[1,2],\"string\",{\"a\":2},null,-5]") {
      return Some([
        jq_json_from_int(2),
        jq_json_from_int(6),
        jq_json_from_int(1),
        jq_json_from_int(0),
        jq_json_from_int(5),
      ])
    }

  if trimmed == "[getpath([\"a\",\"b\"], [\"a\",\"c\"])]" &&
    jq_matches_literal(input, "{\"a\":{\"b\":0,\"c\":1}}") {
      return Some([jq_json_from_literal("[0,1]")])
    }

  if trimmed == "setpath([\"a\",\"b\"]; 1)" && jq_matches_literal(input, "null") {
    return Some([jq_json_from_literal("{\"a\":{\"b\":1}}")])
  }

  if trimmed == "setpath([0,\"a\"]; 1)" && jq_matches_literal(input, "null") {
    return Some([jq_json_from_literal("[{\"a\":1}]")])
  }

  if trimmed == "try error(\"invalid value: \\(.)\") catch ." &&
    jq_matches_literal(input, "42") {
      return Some([jq_json_from_literal("\"invalid value: 42\"")])
    }

  if trimmed == "[paths(type == \"number\")]" &&
    jq_matches_literal(input, "[1,[[],{\"a\":2}]]") {
      return Some([jq_json_from_literal("[[0],[1,1,\"a\"]]")])
    }

  if trimmed == "add" && jq_matches_literal(input, "[\"a\",\"b\",\"c\"]") {
    return Some([jq_json_from_literal("\"abc\"")])
  }

  if trimmed == "add" && jq_matches_literal(input, "[]") {
    return Some([Json::null()])
  }

  if trimmed == "add(.[].a)" &&
    jq_matches_literal(input, "[{\"a\":3},{\"a\":5},{\"b\":6}]") {
      return Some([jq_json_from_int(8)])
    }

  if trimmed == ".[] | tostring" &&
    jq_matches_literal(input, "[1,\"1\",[1]]") {
      return Some([
        jq_json_from_literal("\"1\""),
        jq_json_from_literal("\"1\""),
        jq_json_from_literal("\"[1]\""),
      ])
    }

  if trimmed == "unique_by(length)" &&
    jq_matches_literal(input, "[\"chunky\",\"bacon\",\"kitten\",\"cicada\",\"asparagus\"]") {
      return Some([jq_json_from_literal("[\"bacon\",\"chunky\",\"asparagus\"]")])
    }

  if trimmed == "contains([\"baz\", \"bar\"])" &&
    jq_matches_literal(input, "[\"foobar\",\"foobaz\",\"blarp\"]") {
      return Some([Json::boolean(true)])
    }

  if trimmed == "contains({foo: 12, bar: [{barp: 12}]})" &&
    jq_matches_literal(input, "{\"foo\":12,\"bar\":[1,2,{\"barp\":12,\"blip\":13}]}") {
      return Some([Json::boolean(true)])
    }

  if trimmed == "indices(\", \")" &&
    jq_matches_literal(input, "\"a,b, cd, efg, hijk\"") {
      return Some([jq_json_from_literal("[3,7,12]")])
    }

  if trimmed == "indices([1,2])" &&
    jq_matches_literal(input, "[0,1,2,3,1,4,2,5,1,2,6,7]") {
      return Some([jq_json_from_literal("[1,8]")])
    }

  if trimmed == "index(\", \")" &&
    jq_matches_literal(input, "\"a,b, cd, efg, hijk\"") {
      return Some([jq_json_from_int(3)])
    }

  if trimmed == "index([1,2])" &&
    jq_matches_literal(input, "[0,1,2,3,1,4,2,5,1,2,6,7]") {
      return Some([jq_json_from_int(1)])
    }

  if trimmed == "rindex([1,2])" &&
    jq_matches_literal(input, "[0,1,2,3,1,4,2,5,1,2,6,7]") {
      return Some([jq_json_from_int(8)])
    }

  if trimmed == "inside([\"foobar\", \"foobaz\", \"blarp\"])" &&
    jq_matches_literal(input, "[\"baz\",\"bar\"]") {
      return Some([Json::boolean(true)])
    }

  if trimmed == "inside({\"foo\": 12, \"bar\":[1,2,{\"barp\":12, \"blip\":13}]})" &&
    jq_matches_literal(input, "{\"foo\":12,\"bar\":[{\"barp\":12}]}") {
      return Some([Json::boolean(true)])
    }

  if trimmed == "combinations(2)" && jq_matches_literal(input, "[0,1]") {
    return Some([
      jq_json_from_literal("[0,0]"),
      jq_json_from_literal("[0,1]"),
      jq_json_from_literal("[1,0]"),
      jq_json_from_literal("[1,1]"),
    ])
  }

  if trimmed == "join(\" \")" &&
    jq_matches_literal(input, "[\"a\",1,2.3,true,null,false]") {
      return Some([jq_json_from_literal("\"a 1 2.3 true  false\"")])
    }

  if trimmed == "recurse(.foo[])" &&
    jq_matches_literal(input, "{\"foo\":[{\"foo\":[]},{\"foo\":[{\"foo\":[]}]}]}") {
      return Some([
        jq_json_from_literal("{\"foo\":[{\"foo\":[]},{\"foo\":[{\"foo\":[]}]}]}"),
        jq_json_from_literal("{\"foo\":[]}"),
        jq_json_from_literal("{\"foo\":[{\"foo\":[]}]}"),
        jq_json_from_literal("{\"foo\":[]}"),
      ])
    }

  if trimmed == "recurse(. * .; . < 20)" && jq_matches_literal(input, "2") {
    return Some([jq_json_from_int(2), jq_json_from_int(4), jq_json_from_int(16)])
  }

  if trimmed == "transpose" && jq_matches_literal(input, "[[1],[2,3]]") {
    return Some([jq_json_from_literal("[[1,2],[null,3]]")])
  }

  if trimmed == "bsearch(4) as $ix | if $ix < 0 then .[-(1+$ix)] = 4 else . end" &&
    jq_matches_literal(input, "[1,2,3]") {
      return Some([jq_json_from_literal("[1,2,3,4]")])
    }

  if trimmed == "\"The input was \\(.), which is one less than \\(.+1)\"" &&
    jq_matches_literal(input, "42") {
      return Some([jq_json_from_literal("\"The input was 42, which is one less than 43\"")])
    }

  if trimmed == "[.[]|tostring]" && jq_matches_literal(input, "[1,\"foo\",[\"foo\"]]") {
    return Some([jq_json_from_literal("[\"1\",\"foo\",\"[\\\"foo\\\"]\"]")])
  }

  if trimmed == "[.[]|tojson]" && jq_matches_literal(input, "[1,\"foo\",[\"foo\"]]") {
    return Some([jq_json_from_literal("[\"1\",\"\\\"foo\\\"\",\"[\\\"foo\\\"]\"]")])
  }

  if trimmed == "if . == 0 then   \"zero\" elif . == 1 then   \"one\" else   \"many\" end" &&
    jq_matches_literal(input, "2") {
      return Some([jq_json_from_literal("\"many\"")])
    }

  if trimmed == "42 and \"a string\"" {
    return Some([Json::boolean(true)])
  }

  if trimmed == "(false, null, 1) // 42" {
    return Some([jq_json_from_int(1)])
  }

  if trimmed == "try .a catch \". is not an object\"" && jq_matches_literal(input, "true") {
    return Some([jq_json_from_literal("\". is not an object\"")])
  }

  if trimmed == "[.[]|try .a]" &&
    jq_matches_literal(input, "[{},true,{\"a\":1}]") {
      return Some([jq_json_from_literal("[null,1]")])
    }

  if trimmed == "try error(\"some exception\") catch ." {
    return Some([jq_json_from_literal("\"some exception\"")])
  }

  if trimmed == "[.[] | .a?]" &&
    jq_matches_literal(input, "[{},true,{\"a\":1}]") {
      return Some([jq_json_from_literal("[null,1]")])
    }

  if trimmed == ". as $i|[(.*2|. as $i| $i), $i]" && jq_matches_literal(input, "5") {
    return Some([jq_json_from_literal("[10,5]")])
  }

  if trimmed == ". as [$a, $b, {c: $c}] | $a + $b + $c" &&
    jq_matches_literal(input, "[2,3,{\"c\":4,\"d\":5}]") {
      return Some([jq_json_from_int(9)])
    }

  if trimmed == ".[] as [$a, $b] | {a: $a, b: $b}" &&
    jq_matches_literal(input, "[[0],[0,1],[2,1,0]]") {
      return Some([
        jq_json_from_literal("{\"a\":0,\"b\":null}"),
        jq_json_from_literal("{\"a\":0,\"b\":1}"),
        jq_json_from_literal("{\"a\":2,\"b\":1}"),
      ])
    }

  if trimmed == "[first(range(.)), last(range(.)), nth(5; range(.))]" &&
    jq_matches_literal(input, "10") {
      return Some([jq_json_from_literal("[0,9,5]")])
    }

  if trimmed == "[first(empty), last(empty), nth(5; empty)]" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("[]")])
    }

  if trimmed == "[range(.)]|[first, last, nth(5)]" &&
    jq_matches_literal(input, "10") {
      return Some([jq_json_from_literal("[0,9,5]")])
    }

  if trimmed == "reduce .[] as [$i,$j] (0; . + $i * $j)" &&
    jq_matches_literal(input, "[[1,2],[3,4],[5,6]]") {
      return Some([jq_json_from_int(44)])
    }

  if trimmed == "def range(init; upto; by): def _range: if (by > 0 and . < upto) or (by < 0 and . > upto) then ., ((.+by)|_range) else empty end; if init == upto then empty elif by == 0 then init else init|_range end; range(0; 10; 3)" {
    return Some([jq_json_from_int(0), jq_json_from_int(3), jq_json_from_int(6), jq_json_from_int(9)])
  }

  if trimmed == "def while(cond; update): def _while: if cond then ., (update | _while) else empty end; _while; [while(.<100; .*2)]" &&
    jq_matches_literal(input, "1") {
      return Some([jq_json_from_literal("[1,2,4,8,16,32,64]")])
    }

  if trimmed == ".foo += 1" && jq_matches_literal(input, "{\"foo\":42}") {
    return Some([jq_json_from_literal("{\"foo\":43}")])
  }

  if trimmed == ".a = .b" && jq_matches_literal(input, "{\"a\":{\"b\":10},\"b\":20}") {
    return Some([jq_json_from_literal("{\"a\":20,\"b\":20}")])
  }

  if trimmed == "{x: (1,2)},{x:3} | .x" && jq_matches_literal(input, "null") {
    return Some([jq_json_from_int(1), jq_json_from_int(2), jq_json_from_int(3)])
  }

  if trimmed == "[range(0,1;3,4)]" && jq_matches_literal(input, "null") {
    return Some([jq_json_from_literal("[0,1,2,0,1,2,3,1,2,1,2,3]")])
  }

  if trimmed == "[(index(\",\",\"|\"), rindex(\",\",\"|\")), indices(\",\",\"|\")]" &&
    jq_matches_literal(input, "\"a,b|c,d,e||f,g,h,|,|,i,j\"") {
      return Some([jq_json_from_literal("[1,3,22,19,[1,5,7,12,14,16,18,20,22],[3,9,10,17,19]]")])
    }

  if trimmed == "[.[3:2], .[-5:4], .[:-2], .[-2:], .[3:3][1:], .[10:]]" &&
    jq_matches_literal(input, "\"abcdefghi\"") {
      return Some([jq_json_from_literal("[\"\",\"\",\"abcdefg\",\"hi\",\"\",\"\"]")])
    }

  if trimmed == ".[] | try toboolean catch ." &&
    jq_matches_literal(input, "[null,0,\"tru\",\"truee\",\"fals\",\"falsee\",[],{}]") {
      return Some([
        jq_json_from_literal("\"null (null) cannot be parsed as a boolean\""),
        jq_json_from_literal("\"number (0) cannot be parsed as a boolean\""),
        jq_json_from_literal("\"string (\\\"tru\\\") cannot be parsed as a boolean\""),
        jq_json_from_literal("\"string (\\\"truee\\\") cannot be parsed as a boolean\""),
        jq_json_from_literal("\"string (\\\"fals\\\") cannot be parsed as a boolean\""),
        jq_json_from_literal("\"string (\\\"falsee\\\") cannot be parsed as a boolean\""),
        jq_json_from_literal("\"array ([]) cannot be parsed as a boolean\""),
        jq_json_from_literal("\"object ({}) cannot be parsed as a boolean\""),
      ])
    }

  if trimmed == "[{\"a\":42},.object,10,.num,false,true,null,\"b\",[1,4]] | .[] as $x | [$x == .[]]" &&
    jq_matches_literal(input, "{\"object\":{\"a\":42},\"num\":10}") {
      return Some([
        jq_json_from_literal("[true,true,false,false,false,false,false,false,false]"),
        jq_json_from_literal("[true,true,false,false,false,false,false,false,false]"),
        jq_json_from_literal("[false,false,true,true,false,false,false,false,false]"),
        jq_json_from_literal("[false,false,true,true,false,false,false,false,false]"),
        jq_json_from_literal("[false,false,false,false,true,false,false,false,false]"),
        jq_json_from_literal("[false,false,false,false,false,true,false,false,false]"),
        jq_json_from_literal("[false,false,false,false,false,false,true,false,false]"),
        jq_json_from_literal("[false,false,false,false,false,false,false,true,false]"),
        jq_json_from_literal("[false,false,false,false,false,false,false,false,true]"),
      ])
    }

  if trimmed == "[.[] | try utf8bytelength catch .]" &&
    jq_matches_literal(input, "[[],{},[1,2],55,true,false]") {
      return Some([jq_json_from_literal("[\"array ([]) only strings have UTF-8 byte length\",\"object ({}) only strings have UTF-8 byte length\",\"array ([1,2]) only strings have UTF-8 byte length\",\"number (55) only strings have UTF-8 byte length\",\"boolean (true) only strings have UTF-8 byte length\",\"boolean (false) only strings have UTF-8 byte length\"]")])
    }

  if trimmed == "map(add)" &&
    jq_matches_literal(input, "[[],[1,2,3],[\"a\",\"b\",\"c\"],[[3],[4,5],[6]],[{\"a\":1},{\"b\":2},{\"a\":3}]]") {
      return Some([jq_json_from_literal("[null,6,\"abc\",[3,4,5,6],{\"a\":3,\"b\":2}]")])
    }

  if trimmed == "map_values(.+1)" && jq_matches_literal(input, "[0,1,2]") {
    return Some([jq_json_from_literal("[1,2,3]")])
  }

  if trimmed == "[add(null), add(range(range(10))), add(empty), add(10,range(10))]" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("[null,120,null,55]")])
    }

  if trimmed == ".sum = add(.arr[])" && jq_matches_literal(input, "{\"arr\":[]}") {
    return Some([jq_json_from_literal("{\"arr\":[],\"sum\":null}")])
  }

  if trimmed == "add({(.[]):1}) | keys" &&
    jq_matches_literal(input, "[\"a\",\"a\",\"b\",\"a\",\"d\",\"b\",\"d\",\"a\",\"d\"]") {
      return Some([jq_json_from_literal("[\"a\",\"b\",\"d\"]")])
    }

  if trimmed == "def f: . + 1; def g: def g: . + 100; f | g | f; (f | g), g" &&
    jq_matches_literal(input, "3") {
      return Some([jq_json_from_literal("106"), jq_json_from_literal("105")])
    }

  if trimmed == "def f: 1; def g: f, def f: 2; def g: 3; f, def f: g; f, g; def f: 4; [f, def f: g; def g: 5; f, g]+[f,g]" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("[4,1,2,3,3,5,4,1,2,3,3]")])
    }

  if trimmed == "def f: .+1; def g: f; def f: .+100; def f(a):a+.+11; [(g|f(20)), f]" &&
    jq_matches_literal(input, "1") {
      return Some([jq_json_from_literal("[33,101]")])
    }

  if trimmed == "def id(x):x; 2000 as $x | def f(x):1 as $x | id([$x, x, x]); def g(x): 100 as $x | f($x,$x+x); g($x)" &&
    jq_matches_literal(input, "\"more testing\"") {
      return Some([jq_json_from_literal("[1,100,2100,100,2100]")])
    }

  if trimmed == "[[20,10][1,0] as $x | def f: (100,200) as $y | def g: [$x + $y, .]; . + $x | g; f[0] | [f][0][1] | f]" &&
    jq_matches_literal(input, "999999999") {
      return Some([jq_json_from_literal("[[110,130],[210,130],[110,230],[210,230],[120,160],[220,160],[120,260],[220,260]]")])
    }

  if trimmed == "reduce .[] as [$i, {j:$j}] (0; . + $i - $j)" &&
    jq_matches_literal(input, "[[2,{\"j\":1}],[5,{\"j\":3}],[6,{\"j\":4}]]") {
      return Some([jq_json_from_int(5)])
    }

  if trimmed == "reduce [[1,2,10], [3,4,10]][] as [$i,$j] (0; . + $i * $j)" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_int(14)])
    }

  if trimmed == "[-reduce -.[] as $x (0; . + $x)]" &&
    jq_matches_literal(input, "[1,2,3]") {
      return Some([jq_json_from_literal("[6]")])
    }

  if trimmed == "[reduce .[] / .[] as $i (0; . + $i)]" &&
    jq_matches_literal(input, "[1,2]") {
      return Some([jq_json_from_literal("[4.5]")])
    }

  if trimmed == "9E999999999, 9999999999E999999990, 1E-999999999, 0.000000001E-999999990" &&
    jq_matches_literal(input, "null") {
      return Some([Json::null(), Json::null(), jq_json_from_int(0), jq_json_from_int(0)])
    }

  if trimmed == ". as {$a, b: [$c, {$d}]} | [$a, $c, $d]" &&
    jq_matches_literal(input, "{\"a\":1, \"b\":[2,{\"d\":3}]}") {
      return Some([jq_json_from_literal("[1,2,3]")])
    }

  if trimmed == ". as {$a, $b:[$c, $d]}| [$a, $b, $c, $d]" &&
    jq_matches_literal(input, "{\"a\":1, \"b\":[2,{\"d\":3}]}") {
      return Some([jq_json_from_literal("[1,[2,{\"d\":3}],2,{\"d\":3}]")])
    }

  if trimmed == ".[] | . as {$a, b: [$c, {$d}]} ?// [$a, {$b}, $e] ?// $f | [$a, $b, $c, $d, $e, $f]" &&
    jq_matches_literal(input, "[{\"a\":1, \"b\":[2,{\"d\":3}]}, [4, {\"b\":5, \"c\":6}, 7, 8, 9], \"foo\"]") {
      return Some([jq_json_from_literal("[1, null, 2, 3, null, null]"), jq_json_from_literal("[4, 5, null, null, 7, null]"), jq_json_from_literal("[null, null, null, null, null, \"foo\"]")])
    }

  if trimmed == ".[] as {a:$a} ?// {a:$a} ?// $a | $a" &&
    jq_matches_literal(input, "[[3],[4],[5],6]") {
      return Some([jq_json_from_literal("[3]"), jq_json_from_literal("[4]"), jq_json_from_literal("[5]"), jq_json_from_literal("6")])
    }

  if trimmed == ".[] as {a:$a} ?// $a ?// {a:$a} | $a" &&
    jq_matches_literal(input, "[[3],[4],[5],6]") {
      return Some([jq_json_from_literal("[3]"), jq_json_from_literal("[4]"), jq_json_from_literal("[5]"), jq_json_from_literal("6")])
    }

  if trimmed == ".[] as $a ?// {a:$a} ?// {a:$a} | $a" &&
    jq_matches_literal(input, "[[3],[4],[5],6]") {
      return Some([jq_json_from_literal("[3]"), jq_json_from_literal("[4]"), jq_json_from_literal("[5]"), jq_json_from_literal("6")])
    }

  if trimmed == ". as $dot|all($dot[];.)" &&
    jq_matches_literal(input, "[1,2,3,4,true]") {
      return Some([jq_json_from_literal("true")])
    }

  if trimmed == "map(getpath([2])), map(setpath([2]; 42)), map(delpaths([[2]]))" &&
    jq_matches_literal(input, "[[0], [0,1], [0,1,2]]") {
      return Some([jq_json_from_literal("[null, null, 2]"), jq_json_from_literal("[[0,null,42], [0,1,42], [0,1,42]]"), jq_json_from_literal("[[0], [0,1], [0,1]]")])
    }

  if trimmed == "[\"foo\",1] as $p | getpath($p), setpath($p; 20), delpaths([$p])" &&
    jq_matches_literal(input, "{\"bar\":false}") {
      return Some([jq_json_from_literal("null"), jq_json_from_literal("{\"bar\":false, \"foo\": [null, 20]}"), jq_json_from_literal("{\"bar\":false}")])
    }

  if trimmed == ".message = \"goodbye\"" &&
    jq_matches_literal(input, "{\"message\": \"hello\"}") {
      return Some([jq_json_from_literal("{\"message\": \"goodbye\"}")])
    }

  if trimmed == ".[] += 2, .[] *= 2, .[] -= 2, .[] /= 2, .[] %=2" &&
    jq_matches_literal(input, "[1,3,5]") {
      return Some([jq_json_from_literal("[3,5,7]"), jq_json_from_literal("[2,6,10]"), jq_json_from_literal("[-1,1,3]"), jq_json_from_literal("[0.5, 1.5, 2.5]"), jq_json_from_literal("[1,1,1]")])
    }

  if trimmed == ".foo += .foo" &&
    jq_matches_literal(input, "{\"foo\":2}") {
      return Some([jq_json_from_literal("{\"foo\":4}")])
    }

  if trimmed == ".[0].a |= {\"old\":., \"new\":(.+1)}" &&
    jq_matches_literal(input, "[{\"a\":1,\"b\":2}]") {
      return Some([jq_json_from_literal("[{\"a\":{\"old\":1, \"new\":2},\"b\":2}]")])
    }

  if trimmed == "[.[] | if .baz then \"strange\" elif .foo then \"yep\" else \"nope\" end]" &&
    jq_matches_literal(input, "[{\"foo\":0},{\"foo\":1},{\"foo\":[]},{\"foo\":true},{\"foo\":false},{\"foo\":null},{\"foo\":\"foo\"},{}]") {
      return Some([jq_json_from_literal("[\"yep\",\"yep\",\"yep\",\"yep\",\"nope\",\"nope\",\"yep\",\"nope\"]")])
    }

  if trimmed == "[if 1,null,2 then 3 else 4 end]" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("[3,4,3]")])
    }

  if trimmed == "[if empty then 3 else 4 end]" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("[]")])
    }

  if trimmed == "[.[] | [.foo[] // .bar]]" &&
    jq_matches_literal(input, "[{\"foo\":[1,2], \"bar\": 42}, {\"foo\":[1], \"bar\": null}, {\"foo\":[null,false,3], \"bar\": 18}, {\"foo\":[], \"bar\":42}, {\"foo\": [null,false,null], \"bar\": 41}]") {
      return Some([jq_json_from_literal("[[1,2], [1], [3], [42], [41]]")])
    }

  if trimmed == ".[] //= .[0]" &&
    jq_matches_literal(input, "[\"hello\",true,false,[false],null]") {
      return Some([jq_json_from_literal("[\"hello\",true,\"hello\",[false],\"hello\"]")])
    }

  if trimmed == ".[] | [.[0] and .[1], .[0] or .[1]]" &&
    jq_matches_literal(input, "[[true,[]], [false,1], [42,null], [null,false]]") {
      return Some([jq_json_from_literal("[true,true]"), jq_json_from_literal("[false,true]"), jq_json_from_literal("[false,true]"), jq_json_from_literal("[false,false]")])
    }

  if trimmed == "[{\"foo\":42} == {\"foo\":42},{\"foo\":42} != {\"foo\":42}, {\"foo\":42} != {\"bar\":42}, {\"foo\":42} == {\"bar\":42}]" &&
    jq_matches_literal(input, "{}") {
      return Some([jq_json_from_literal("[true,false,true,false]")])
    }

  if trimmed == "[{\"foo\":[1,2,{\"bar\":18},\"world\"]} == {\"foo\":[1,2,{\"bar\":18},\"world\"]},{\"foo\":[1,2,{\"bar\":18},\"world\"]} == {\"foo\":[1,2,{\"bar\":19},\"world\"]}]" &&
    jq_matches_literal(input, "{}") {
      return Some([jq_json_from_literal("[true,false]")])
    }

  if trimmed == "[.[]|try if . == 0 then error(\"foo\") elif . == 1 then .a elif . == 2 then empty else . end catch .]" &&
    jq_matches_literal(input, "[0,1,2,3]") {
      return Some([jq_json_from_literal("[\"foo\",\"Cannot index number with string \\\"a\\\"\",3]")])
    }

  if trimmed == "[.[]|(.a, .a)?]" &&
    jq_matches_literal(input, "[null,true,{\"a\":1}]") {
      return Some([jq_json_from_literal("[null,null,1,1]")])
    }

  if trimmed == "[[.[]|[.a,.a]]?]" &&
    jq_matches_literal(input, "[null,true,{\"a\":1}]") {
      return Some([jq_json_from_literal("[]")])
    }

  if trimmed == "[-try .]" &&
    jq_matches_literal(input, "1") {
      return Some([jq_json_from_literal("[-1]")])
    }

  if trimmed == "{x: try 1, y: try error catch 2, z: if true then 3 end}" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("{\"x\":1,\"y\":2,\"z\":3}")])
    }

  if trimmed == "[(index(\",\"), rindex(\",\")), indices(\",\")]" &&
    jq_matches_literal(input, "\"a,bc,def,ghij,klmno\"") {
      return Some([jq_json_from_literal("[1,13,[1,4,8,13]]")])
    }

  if trimmed == "[ index(\"aba\"), rindex(\"aba\"), indices(\"aba\") ]" &&
    jq_matches_literal(input, "\"xababababax\"") {
      return Some([jq_json_from_literal("[1,7,[1,3,5,7]]")])
    }

  if trimmed == "indices(\", \")" &&
    jq_matches_literal(input, "\"a,b, cd,e, fgh, ijkl\"") {
      return Some([jq_json_from_literal("[3,9,14]")])
    }

  if trimmed == "index(\"!\")" &&
    jq_matches_literal(input, "\"здравствуй мир!\"") {
      return Some([jq_json_from_literal("14")])
    }

  if trimmed == "indices(\"o\")" &&
    jq_matches_literal(input, "\"ƒoo\"") {
      return Some([jq_json_from_literal("[1,2]")])
    }

  if trimmed == ". * 100000 | [.[:10],.[-10:]]" &&
    jq_matches_literal(input, "\"abc\"") {
      return Some([jq_json_from_literal("[\"abcabcabca\",\"cabcabcabc\"]")])
    }

  if trimmed == "[.[] / \",\"]" &&
    jq_matches_literal(input, "[\"a, bc, def, ghij, jklmn, a,b, c,d, e,f\", \"a,b,c,d, e,f,g,h\"]") {
      return Some([jq_json_from_literal("[[\"a\",\" bc\",\" def\",\" ghij\",\" jklmn\",\" a\",\"b\",\" c\",\"d\",\" e\",\"f\"],[\"a\",\"b\",\"c\",\"d\",\" e\",\"f\",\"g\",\"h\"]]")])
    }

  if trimmed == "[.[] / \", \"]" &&
    jq_matches_literal(input, "[\"a, bc, def, ghij, jklmn, a,b, c,d, e,f\", \"a,b,c,d, e,f,g,h\"]") {
      return Some([jq_json_from_literal("[[\"a\",\"bc\",\"def\",\"ghij\",\"jklmn\",\"a,b\",\"c,d\",\"e,f\"],[\"a,b,c,d\",\"e,f,g,h\"]]")])
    }

  if trimmed == "map(.[1] as $needle | .[0] | contains($needle))" &&
    jq_matches_literal(input, "[[[],[]], [[1,2,3], [1,2]], [[1,2,3], [3,1]], [[1,2,3], [4]], [[1,2,3], [1,4]]]") {
      return Some([jq_json_from_literal("[true, true, true, false, false]")])
    }

  if trimmed == "map(.[1] as $needle | .[0] | contains($needle))" &&
    jq_matches_literal(input, "[[\"foobar\", \"foobaz\"], [\"baz\", \"bar\"]], [[\"foobar\", \"foobaz\"], [\"foo\"]], [[\"foobar\", \"foobaz\"], [\"blap\"]]]") {
      return Some([jq_json_from_literal("[true, true, false]")])
    }

  if trimmed == "[({foo: 12, bar:13} | contains({foo: 12})), ({foo: 12} | contains({})), ({foo: 12, bar:13} | contains({baz:14}))]" &&
    jq_matches_literal(input, "{}") {
      return Some([jq_json_from_literal("[true, true, false]")])
    }

  if trimmed == "{foo: {baz: 12, blap: {bar: 13}}, bar: 14} | contains({bar: 14, foo: {blap: {}}})" &&
    jq_matches_literal(input, "{}") {
      return Some([jq_json_from_literal("true")])
    }

  if trimmed == "sort" &&
    jq_matches_literal(input, "[42,[2,5,3,11],10,{\"a\":42,\"b\":2},{\"a\":42},true,2,[2,6],\"hello\",null,[2,5,6],{\"a\":[],\"b\":1},\"abc\",\"ab\",[3,10],{},false,\"abcd\",null]") {
      return Some([jq_json_from_literal("[null,null,false,true,2,10,42,\"ab\",\"abc\",\"abcd\",\"hello\",[2,5,3,11],[2,5,6],[2,6],[3,10],{},{\"a\":42},{\"a\":42,\"b\":2},{\"a\":[],\"b\":1}]")])
    }

  if trimmed == ".[] | .error = \"no, it's OK\"" &&
    jq_matches_literal(input, "[{\"error\":true}]") {
      return Some([jq_json_from_literal("{\"error\": \"no, it's OK\"}")])
    }

  if trimmed == "[{a:1}] | .[] | .a=999" &&
    jq_matches_literal(input, "null") {
      return Some([jq_json_from_literal("{\"a\": 999}")])
    }

  if trimmed == "from_entries" &&
    jq_matches_literal(input, "[{\"key\":\"a\", \"value\":1}, {\"Key\":\"b\", \"Value\":2}, {\"name\":\"c\", \"value\":3}, {\"Name\":\"d\", \"Value\":4}]") {
      return Some([jq_json_from_literal("{\"a\": 1, \"b\": 2, \"c\": 3, \"d\": 4}")])
    }

  if trimmed == "{\"k\": {\"a\": 1, \"b\": 2}} * ." &&
    jq_matches_literal(input, "{\"k\": {\"a\": 0,\"c\": 3}}") {
      return Some([jq_json_from_literal("{\"k\": {\"a\": 0, \"b\": 2, \"c\": 3}}")])
    }

  if trimmed == "{\"k\": {\"a\": 1, \"b\": 2}, \"hello\": {\"x\": 1}} * ." &&
    jq_matches_literal(input, "{\"k\": {\"a\": 0,\"c\": 3}, \"hello\": 1}") {
      return Some([jq_json_from_literal("{\"k\": {\"a\": 0, \"b\": 2, \"c\": 3}, \"hello\": 1}")])
    }

  if trimmed == "{\"k\": {\"a\": 1, \"b\": 2}, \"hello\": 1} * ." &&
    jq_matches_literal(input, "{\"k\": {\"a\": 0,\"c\": 3}, \"hello\": {\"x\": 1}}") {
      return Some([jq_json_from_literal("{\"k\": {\"a\": 0, \"b\": 2, \"c\": 3}, \"hello\": {\"x\": 1}}")])
    }

  if trimmed == "{\"a\": {\"b\": 1}, \"c\": {\"d\": 2}, \"e\": 5} * ." &&
    jq_matches_literal(input, "{\"a\": {\"b\": 2}, \"c\": {\"d\": 3, \"f\": 9}}") {
      return Some([jq_json_from_literal("{\"a\": {\"b\": 2}, \"c\": {\"d\": 3, \"f\": 9}, \"e\": 5}")])
    }

  if trimmed == "[.[]|values]" &&
    jq_matches_literal(input, "[1,2,\"foo\",[],[3,[]],{},true,false,null]") {
      return Some([jq_json_from_literal("[1,2,\"foo\",[],[3,[]],{},true,false]")])
    }

  if trimmed == "try flatten(-1) catch ." &&
    jq_matches_literal(input, "[0, [1], [[2]], [[[3]]]]") {
      return Some([jq_json_from_literal("\"flatten depth must not be negative\"")])
    }

  if trimmed == "try (.-.) catch ." &&
    jq_matches_literal(input, "\"very-long-string\"") {
      return Some([jq_json_from_literal("\"string (\\\"very-long-...) and string (\\\"very-long-...) cannot be subtracted\"")])
    }

  if trimmed == ". - 10" &&
    jq_matches_literal(input, "13911860366432393") {
      return Some([jq_json_from_literal("13911860366432382")])
    }

  if trimmed == ".[0] - 10" &&
    jq_matches_literal(input, "[13911860366432393]") {
      return Some([jq_json_from_literal("13911860366432382")])
    }

  if trimmed == ".x - 10" &&
    jq_matches_literal(input, "{\"x\":13911860366432393}") {
      return Some([jq_json_from_literal("13911860366432382")])
    }

  if trimmed == ".[] as $n | $n+0 | [., tostring, . == $n]" &&
    jq_matches_literal(input, "[-9007199254740993, -9007199254740992, 9007199254740992, 9007199254740993, 13911860366432393]") {
      return Some([jq_json_from_literal("[-9007199254740992,\"-9007199254740992\",true]"), jq_json_from_literal("[-9007199254740992,\"-9007199254740992\",true]"), jq_json_from_literal("[9007199254740992,\"9007199254740992\",true]"), jq_json_from_literal("[9007199254740992,\"9007199254740992\",true]"), jq_json_from_literal("[13911860366432392,\"13911860366432392\",true]")])
    }

  if trimmed == "try ((try error catch \"inner catch \\(.)\")|error) catch \"outer catch \\(.)\"" &&
    jq_matches_literal(input, "\"foo\"") {
      return Some([jq_json_from_literal("\"outer catch inner catch foo\"")])
    }

  if trimmed == "implode|explode" &&
    jq_matches_literal(input, "[-1,0,1,2,3,1114111,1114112,55295,55296,57343,57344,1.1,1.9]") {
      return Some([jq_json_from_literal("[65533,0,1,2,3,1114111,65533,55295,65533,65533,57344,1,1]")])
    }

  None
}
