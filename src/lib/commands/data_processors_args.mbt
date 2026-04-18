// moon_bash Commands - Data processor argument parsing

///|
priv struct XanSliceConfig {
  start : Int
  length : Int?
  file_path : String?
}

///|
priv struct YqConfig {
  raw : Bool
  filter : String
  file_path : String?
}

///|
priv struct CsvlookConfig {
  file_path : String?
}

///|
fn xan_slice_normalize_args(args : Array[String]) -> Array[String] {
  let normalized : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if (arg == "-i" || arg == "-l") && i + 1 < args.length() {
      normalized.push(arg)
      normalized.push(args[i + 1])
      i += 2
    } else if !arg.has_prefix("-") {
      normalized.push(arg)
      i += 1
    } else {
      // Preserve legacy behavior: unsupported flags and missing values are ignored.
      i += 1
    }
  }
  normalized
}

///|
fn xan_slice_parse_args(args : Array[String]) -> XanSliceConfig {
  let normalized = xan_slice_normalize_args(args)
  let aliases : Map[String, String] = { "i": "index", "l": "length" }
  let parsed = @parse_args.parse(
    normalized,
    options=["index", "length"],
    aliases~,
    double_dash=false,
  ) catch {
    _ =>
      return {
        start: 0,
        length: None,
        file_path: None,
      }
  }

  {
    start: cmd_parse_int(parsed.options.get("index").unwrap_or("0")).to_int(),
    length: match parsed.options.get("length") {
      Some(value) => Some(cmd_parse_int(value).to_int())
      None => None
    },
    file_path: if parsed.positional.length() > 0 {
      Some(parsed.positional[parsed.positional.length() - 1])
    } else {
      None
    },
  }
}

///|
fn yq_parse_args(args : Array[String]) -> YqConfig {
  let normalized : Array[String] = []
  for arg in args {
    if arg == "-r" || arg == "-j" || !(arg.has_prefix("-")) {
      normalized.push(arg)
    }
  }
  let aliases : Map[String, String] = { "r": "raw", "j": "json" }
  let parsed = @parse_args.parse(
    normalized,
    flags=["raw", "json"],
    aliases~,
    double_dash=false,
  ) catch {
    _ => {
      return { raw: false, filter: ".", file_path: None }
    }
  }

  let mut filter = "."
  let mut file_path : String? = None
  for arg in parsed.positional {
    if (filter == "." && arg.has_prefix(".")) || arg == "." {
      filter = arg
    } else {
      file_path = Some(arg)
    }
  }

  {
    raw: parsed.flags.get("raw").unwrap_or(false),
    filter,
    file_path,
  }
}

///|
fn csvlook_parse_args(args : Array[String]) -> CsvlookConfig {
  let parsed = @parse_args.parse(args, double_dash=false) catch {
    _ => return { file_path: None }
  }
  {
    file_path: if parsed.positional.length() > 0 {
      Some(parsed.positional[0])
    } else {
      None
    },
  }
}
