// Shell sed executor - address matching, substitution, and transliteration

fn sed_emit_chunk(
  out : StringBuilder,
  text : String,
  terminated : Bool,
  pending_no_newline : Bool
) -> Bool {
  if pending_no_newline {
    out.write_char('\n')
  }
  out.write_string(text)
  if terminated {
    out.write_char('\n')
    false
  } else {
    true
  }
}

fn sed_find_newline(text : String) -> Int {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int().unsafe_to_char() == '\n' {
      return i
    }
  }
  -1
}

fn sed_find_label_index(
  names : Array[String],
  indices : Array[Int],
  label : String
) -> Int {
  for i = 0; i < names.length(); i = i + 1 {
    if names[i] == label {
      return indices[i]
    }
  }
  -1
}

fn sed_find_group_end(commands : Array[SedCommand], start_idx : Int) -> Int {
  let mut depth = 0
  for i = start_idx; i < commands.length(); i = i + 1 {
    match commands[i].kind {
      GroupStart => depth += 1
      GroupEnd => {
        depth -= 1
        if depth == 0 {
          return i
        }
      }
      _ => ()
    }
  }
  -1
}

fn sed_find_missing_branch_label(commands : Array[SedCommand]) -> String? {
  let labels : Array[String] = []
  for cmd in commands {
    match cmd.kind {
      Label(name) => labels.push(name)
      _ => ()
    }
  }

  for cmd in commands {
    match cmd.kind {
      Branch(label) | BranchIfSubst(label) | BranchIfNotSubst(label) => {
        match label {
          Some(name) => {
            let mut found = false
            for known in labels {
              if known == name {
                found = true
                break
              }
            }
            if not(found) {
              return Some(name)
            }
          }
          None => ()
        }
      }
      _ => ()
    }
  }

  None
}

fn sed_split_lines_with_flags(input : String) -> Array[(String, Bool)] {
  let lines : Array[(String, Bool)] = []
  if input.length() == 0 {
    return lines
  }

  let buf = StringBuilder::new()
  for i = 0; i < input.length(); i = i + 1 {
    let ch = input[i].to_int().unsafe_to_char()
    if ch == '\n' {
      lines.push((buf.to_string(), true))
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }

  let remaining = buf.to_string()
  if remaining.length() > 0 {
    lines.push((remaining, false))
  }
  lines
}

fn ExecContext::sed_append_write(
  self : ExecContext,
  path : String,
  text : String,
  terminated : Bool
) -> Unit {
  let resolved = try {
    @fs.resolve_path(self.cwd, path)
  } catch {
    _ => path
  }

  let existing = match self.fs.entries.get(resolved) {
    Some(@fs.FsEntry::File(file)) => file.content
    _ => ""
  }
  let next = StringBuilder::new()
  next.write_string(existing)
  if existing.length() > 0 &&
    existing[existing.length() - 1].to_int().unsafe_to_char() != '\n' {
    next.write_char('\n')
  }
  next.write_string(text)
  if terminated {
    next.write_char('\n')
  }
  try {
    self.fs.write_file(resolved, next.to_string())
  } catch {
    _ => ()
  }
}

fn sed_address_applies(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  state : SedRangeState,
  last_regex : @regex.GrepMatcher?
) -> (Bool, SedRangeState, @regex.GrepMatcher?) {
  match address {
    None => (
      true,
      sed_empty_range_state(),
      last_regex,
    )
    Some(addr) => match addr.end {
      None => {
        let (hit, next_last) = sed_address_matches(
          addr.start,
          line,
          line_no,
          total_lines,
          last_regex,
        )
        (
          hit,
          sed_empty_range_state(),
          next_last,
        )
      }
      Some(end_addr) => {
        if state.pending_single_line {
          (
            true,
            sed_empty_range_state(),
            last_regex,
          )
        } else if state.in_range {
          match end_addr {
            Relative(_) => {
              if state.relative_end_line >= 0 && line_no >= state.relative_end_line {
                (
                  true,
                  sed_empty_range_state(),
                  last_regex,
                )
              } else {
                (true, state, last_regex)
              }
            }
            _ => {
              let (end_hit, next_last) = sed_address_matches(
                end_addr,
                line,
                line_no,
                total_lines,
                last_regex,
              )
              (
                true,
                {
                  in_range: not(end_hit),
                  relative_end_line: -1,
                  pending_single_line: false,
                },
                next_last,
              )
            }
          }
        } else {
          let (start_hit, last_after_start) = sed_address_matches(
            addr.start,
            line,
            line_no,
            total_lines,
            last_regex,
          )
          if not(start_hit) {
            (
              false,
              sed_empty_range_state(),
              last_after_start,
            )
          } else {
            match end_addr {
              Relative(count) => {
                if count <= 0 {
                  (
                    true,
                    sed_empty_range_state(),
                    last_after_start,
                  )
                } else {
                  (
                    true,
                    {
                      in_range: true,
                      relative_end_line: line_no + count,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              Line(end_line) => {
                if end_line <= line_no {
                  (
                    true,
                    sed_empty_range_state(),
                    last_after_start,
                  )
                } else {
                  (
                    true,
                    {
                      in_range: true,
                      relative_end_line: -1,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              _ => {
                let (end_hit, last_after_end) = sed_address_matches(
                  end_addr,
                  line,
                  line_no,
                  total_lines,
                  last_after_start,
                )
                (
                  true,
                  {
                    in_range: not(end_hit),
                    relative_end_line: -1,
                    pending_single_line: false,
                  },
                  last_after_end,
                )
              }
            }
          }
        }
      }
    }
  }
}

fn sed_address_tick_skipped(
  address : SedAddressRange?,
  line : String,
  line_no : Int,
  total_lines : Int,
  state : SedRangeState,
  last_regex : @regex.GrepMatcher?
) -> (SedRangeState, @regex.GrepMatcher?) {
  match address {
    None => (
      sed_empty_range_state(),
      last_regex,
    )
    Some(addr) => match addr.end {
      None => {
        // Single-address commands do not carry range state across skipped cycles.
        (sed_empty_range_state(), last_regex)
      }
      Some(end_addr) => {
        if state.pending_single_line {
          (state, last_regex)
        } else if state.in_range {
          // When a previous command deleted the cycle, this command is not executed.
          // Keep range active; end-address checks happen only on executed cycles.
          (state, last_regex)
        } else {
          let (start_hit, last_after_start) = sed_address_matches(
            addr.start,
            line,
            line_no,
            total_lines,
            last_regex,
          )
          if not(start_hit) {
            (
              sed_empty_range_state(),
              last_after_start,
            )
          } else {
            match end_addr {
              Relative(count) => {
                if count <= 0 {
                  (
                    {
                      in_range: false,
                      relative_end_line: -1,
                      pending_single_line: true,
                    },
                    last_after_start,
                  )
                } else {
                  (
                    {
                      in_range: true,
                      relative_end_line: line_no + count,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              Line(end_line) => {
                if end_line <= line_no {
                  (
                    {
                      in_range: false,
                      relative_end_line: -1,
                      pending_single_line: true,
                    },
                    last_after_start,
                  )
                } else {
                  (
                    {
                      in_range: true,
                      relative_end_line: -1,
                      pending_single_line: false,
                    },
                    last_after_start,
                  )
                }
              }
              _ => (
                { in_range: true, relative_end_line: -1, pending_single_line: false },
                last_after_start,
              )
            }
          }
        }
      }
    }
  }
}

fn sed_address_matches(
  address : SedAddress,
  line : String,
  line_no : Int,
  total_lines : Int,
  last_regex : @regex.GrepMatcher?
) -> (Bool, @regex.GrepMatcher?) {
  match address {
    Line(n) => (line_no == n, last_regex)
    LastLine => (line_no == total_lines, last_regex)
    Regex(matcher) => (matcher.find_first(line) is Some(_), Some(matcher))
    LastRegex => match last_regex {
      Some(matcher) => (matcher.find_first(line) is Some(_), last_regex)
      None => (false, None)
    }
    Relative(_) => (false, last_regex)
  }
}

fn sed_substitute_line(
  line : String,
  matcher : @regex.GrepMatcher,
  replacement : String,
  global : Bool,
  occurrence : Int,
  literal_ampersand~ : Bool = false
) -> (String, Bool) {
  if not(global) {
    if occurrence > 1 {
      let mut cursor = 0
      let mut seen = 0
      while cursor <= line.length() {
        match matcher.find_first_with_groups(line, start=cursor) {
          Some((start, end, groups)) => {
            seen += 1
            if seen == occurrence {
              let prefix = substring_slice(line, 0, start)
              let matched = substring_slice(line, start, end)
              let suffix = substring_slice(line, end, line.length())
              return (
                prefix +
                apply_sed_replacement(
                  replacement,
                  matched,
                  groups,
                  literal_ampersand~,
                ) +
                suffix,
                true,
              )
            }
            if end > start {
              cursor = end
            } else if start < line.length() {
              cursor = start + 1
            } else {
              break
            }
          }
          None => break
        }
      }
      return (line, false)
    }

    match matcher.find_first_with_groups(line) {
      Some((start, end, groups)) => {
        let prefix = substring_slice(line, 0, start)
        let matched = substring_slice(line, start, end)
        let suffix = substring_slice(line, end, line.length())
        (
          prefix +
          apply_sed_replacement(
            replacement,
            matched,
            groups,
            literal_ampersand~,
          ) +
          suffix,
          true,
        )
      }
      None => (line, false)
    }
  } else {
    let out = StringBuilder::new()
    let mut cursor = 0
    let mut changed = false
    let mut done = false
    let mut last_match_end = -1
    while not(done) {
      match matcher.find_first_with_groups(line, start=cursor) {
        Some((start, end, groups)) => {
          if start < cursor {
            done = true
          } else if start == end && start == last_match_end {
            if start < line.length() {
              out.write_char(line[start].to_int().unsafe_to_char())
              cursor = start + 1
            } else {
              cursor = line.length()
              done = true
            }
          } else {
            out.write_string(substring_slice(line, cursor, start))
            let matched = substring_slice(line, start, end)
            out.write_string(
              apply_sed_replacement(
                replacement,
                matched,
                groups,
                literal_ampersand~,
              ),
            )
            changed = true
            last_match_end = end
            if end > start {
              cursor = end
            } else if start < line.length() {
              out.write_char(line[start].to_int().unsafe_to_char())
              cursor = start + 1
            } else {
              cursor = line.length()
              done = true
            }
          }
        }
        None => done = true
      }
    }
    if cursor <= line.length() {
      out.write_string(substring_slice(line, cursor, line.length()))
    }
    if changed {
      (out.to_string(), true)
    } else {
      (line, false)
    }
  }
}

fn sed_transliterate_line(
  line : String,
  source : String,
  target : String
) -> String {
  if source.length() == 0 || target.length() == 0 {
    return line
  }
  let out = StringBuilder::new()
  for i = 0; i < line.length(); i = i + 1 {
    let ch = line[i]
    let mut replaced = false
    for j = 0; j < source.length(); j = j + 1 {
      if source[j] == ch {
        out.write_char(target[j].to_int().unsafe_to_char())
        replaced = true
        break
      }
    }
    if not(replaced) {
      out.write_char(ch.to_int().unsafe_to_char())
    }
  }
  out.to_string()
}

fn apply_sed_replacement(
  template : String,
  matched : String,
  groups : Array[String],
  literal_ampersand~ : Bool = false
) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < template.length() {
    let ch = template[i].to_int().unsafe_to_char()
    if ch == '\\' {
      if i + 1 < template.length() {
        let next = template[i + 1].to_int().unsafe_to_char()
        if next == '0' {
          out.write_string(matched)
        } else if next >= '1' && next <= '9' {
          let group_idx = next.to_int() - '1'.to_int()
          if group_idx >= 0 && group_idx < groups.length() {
            out.write_string(groups[group_idx])
          }
        } else if next == 'n' {
          out.write_char('\n')
        } else if next == 't' {
          out.write_char('\t')
        } else if next == 'r' {
          out.write_char('\r')
        } else {
          out.write_char(next)
        }
        i += 2
      } else {
        out.write_char('\\')
        i += 1
      }
      continue
    }
    if ch == '&' && not(literal_ampersand) {
      out.write_string(matched)
      i += 1
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}
