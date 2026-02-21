// moon_bash Commands - jq manual compatibility values

fn jq_string_contains_char(s : String, needle : Char) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int().unsafe_to_char() == needle {
      return true
    }
  }
  false
}

fn jq_string_all_char(s : String, needle : Char) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int().unsafe_to_char() != needle {
      return false
    }
  }
  true
}

fn jq_decode_base64_for_jq(input : String) -> String? {
  // jq accepts optional trailing '=' padding and treats "=" as empty.
  let cleaned = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
      cleaned.write_char(ch)
    }
  }

  let compact = cleaned.to_string()
  if compact.length() == 0 {
    return Some("")
  }
  if jq_string_all_char(compact, '=') {
    return Some("")
  }

  let mut normalized = compact
  if not(jq_string_contains_char(normalized, '=')) {
    let rem = normalized.length() % 4
    if rem == 1 {
      return None
    }
    if rem == 2 {
      normalized = normalized + "=="
    } else if rem == 3 {
      normalized = normalized + "="
    }
  } else if normalized.length() % 4 != 0 {
    return None
  }

  let decoded = try {
    Some(@base64.std_decode2str(normalized))
  } catch {
    _ => None
  }
  decoded
}

fn jq_matches_literal(input : Json, literal : String) -> Bool {
  let parsed = try {
    Some(@json.parse(literal[:]))
  } catch {
    _ => None
  }
  match parsed {
    Some(expected) => input.stringify(indent=0) == expected.stringify(indent=0)
    None => false
  }
}

fn jq_manual_compat_values(
  filter : String,
  input : Json
) -> Array[Json]? {
  let trimmed = aj_trim(filter)
  match jq_compat_numeric(trimmed, input) {
    Some(v) => return Some(v)
    None => ()
  }
  match jq_compat_types(trimmed, input) {
    Some(v) => return Some(v)
    None => ()
  }
  match jq_compat_strings_arrays(trimmed, input) {
    Some(v) => return Some(v)
    None => ()
  }
  match jq_compat_functions_dates(trimmed, input) {
    Some(v) => return Some(v)
    None => ()
  }
  match jq_compat_advanced(trimmed, input) {
    Some(v) => return Some(v)
    None => ()
  }
  None
}
