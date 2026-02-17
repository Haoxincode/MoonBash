// moon_bash Interpreter - Sed Types

priv enum SedAddress {
  Line(Int)
  LastLine
  Regex(@regex.GrepMatcher)
  LastRegex
  Relative(Int)
}

priv struct SedAddressRange {
  start : SedAddress
  end : SedAddress?
}

priv struct SedRangeState {
  in_range : Bool
  relative_end_line : Int
  pending_single_line : Bool
}

priv struct SedSubstSpec {
  matcher : @regex.GrepMatcher?
  replacement : String
  global : Bool
  occurrence : Int
  literal_ampersand : Bool
  print_on_subst : Bool
  write_file : String?
}

priv struct SedTranslitSpec {
  source : String
  target : String
}

priv enum SedCommandKind {
  GroupStart
  GroupEnd
  Delete
  DeleteFirstLine
  Substitute(SedSubstSpec)
  AppendNextLine
  NextLine
  Transliterate(SedTranslitSpec)
  PrintPattern
  PrintFirstLine
  PrintLineNumber
  HoldSet
  HoldAppend
  HoldGet
  HoldAppendGet
  ExchangeHold
  AppendText(String)
  InsertText(String)
  ChangeText(String)
  WriteFile(String)
  Label(String)
  Branch(String?)
  BranchIfSubst(String?)
  BranchIfNotSubst(String?)
  VersionCheck(String?)
  Quit
}

priv struct SedCommand {
  address : SedAddressRange?
  kind : SedCommandKind
  negated : Bool
}

priv enum CycleAction {
  Next
  RestartCycle
  BreakCycle
  JumpTo(Int)
  Quit
}

priv struct SedState {
  mut hold_space : String
  mut last_regex : @regex.GrepMatcher?
  mut pending_no_newline : Bool
  mut quit : Bool
  mut executed_steps : Int
}

priv struct SedCycle {
  mut line_no : Int
  mut line : String
  mut line_terminated : Bool
  mut deleted : Bool
  mut consumed_extra : Int
  mut substituted : Bool
  mut stop_after_cycle : Bool
  mut append_queue : Array[String]
}

fn sed_empty_range_state() -> SedRangeState {
  { in_range: false, relative_end_line: -1, pending_single_line: false }
}

