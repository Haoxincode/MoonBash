// moon_bash Commands - Data processor argument parsing

///|
priv struct XanSliceConfig {
  start : Int
  length : Int?
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
