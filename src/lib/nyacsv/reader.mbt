// NyaCSV-compatible reader primitives, adapted for current MoonBit compiler.

pub(all) struct CSVOptions {
  delimiter : Char
  allow_newlines_in_quotes : Bool
  quote_char : Char
  skip_empty_lines : Bool
  trim_spaces : Bool
}

priv trait CSVReader {
  read_char(Self) -> Char?
  peek_char(Self) -> Char?
  is_eof(Self) -> Bool
}

pub(all) struct StringReader {
  source : String
  mut pos : Int
}

impl CSVReader for StringReader with read_char(self) -> Char? {
  if self.pos < self.source.length() {
    let ch = self.source[self.pos].to_int().unsafe_to_char()
    self.pos += 1
    Some(ch)
  } else {
    None
  }
}

impl CSVReader for StringReader with peek_char(self) -> Char? {
  if self.pos < self.source.length() {
    Some(self.source[self.pos].to_int().unsafe_to_char())
  } else {
    None
  }
}

impl CSVReader for StringReader with is_eof(self) -> Bool {
  self.pos >= self.source.length()
}
