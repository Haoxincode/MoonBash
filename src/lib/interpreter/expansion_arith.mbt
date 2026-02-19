// Shell arithmetic expansion - types, helpers, and tokenizer

priv struct ArithValue {
  value : Int64
  target : ArithTarget
}

priv struct ArithParser {
  tokens : Array[String]
  mut pos : Int
}

fn arith_plain(value : Int64) -> ArithValue {
  { value, target: NoTarget }
}

fn arith_with_target(value : Int64, target : ArithTarget) -> ArithValue {
  { value, target }
}

fn ArithParser::peek(self : ArithParser) -> String? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

fn ArithParser::advance(self : ArithParser) -> String? {
  if self.pos < self.tokens.length() {
    let tok = self.tokens[self.pos]
    self.pos += 1
    Some(tok)
  } else {
    None
  }
}

fn ArithParser::match_tok(self : ArithParser, tok : String) -> Bool {
  match self.peek() {
    Some(cur) => {
      if cur == tok {
        self.pos += 1
        true
      } else {
        false
      }
    }
    None => false
  }
}

fn arith_is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
}

fn arith_is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

fn arith_is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

fn arith_is_ident_char(ch : Char) -> Bool {
  arith_is_ident_start(ch) || arith_is_digit(ch)
}

fn arith_is_hex_digit(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'a' && ch <= 'f') ||
  (ch >= 'A' && ch <= 'F')
}

fn arith_is_base_digit_char(ch : Char) -> Bool {
  arith_is_digit(ch) ||
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '@' ||
  ch == '_'
}

fn arith_trim(s : String) -> String {
  let mut start = 0
  let mut end_ = s.length()

  while start < end_ {
    let ch = s[start].to_int().unsafe_to_char()
    if arith_is_space(ch) {
      start += 1
    } else {
      break
    }
  }

  while end_ > start {
    let ch = s[end_ - 1].to_int().unsafe_to_char()
    if arith_is_space(ch) {
      end_ -= 1
    } else {
      break
    }
  }

  s.view(start_offset=start, end_offset=end_).to_string()
}

fn arith_is_identifier_text(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let first = s[0].to_int().unsafe_to_char()
  if not(arith_is_ident_start(first)) {
    return false
  }
  for i = 1; i < s.length(); i = i + 1 {
    if not(arith_is_ident_char(s[i].to_int().unsafe_to_char())) {
      return false
    }
  }
  true
}

fn arith_parse_decimal_str(s : String) -> Int64? {
  if s.length() == 0 {
    return None
  }
  let mut value = 0L
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if not(arith_is_digit(ch)) {
      return None
    }
    value = value * 10L + (ch.to_int() - 48).to_int64()
  }
  Some(value)
}

fn arith_digit_value(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - 48)
  } else if ch >= 'a' && ch <= 'z' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'Z' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else if ch == '@' {
    Some(62)
  } else if ch == '_' {
    Some(63)
  } else {
    None
  }
}

fn arith_parse_base_digits(digits : String, base : Int) -> Int64? {
  if digits.length() == 0 {
    return None
  }
  let mut value = 0L
  for i = 0; i < digits.length(); i = i + 1 {
    let ch = digits[i].to_int().unsafe_to_char()
    match arith_digit_value(ch) {
      Some(d) => {
        if d >= base {
          return None
        }
        value = value * base.to_int64() + d.to_int64()
      }
      None => return None
    }
  }
  Some(value)
}

fn arith_parse_number_literal(token : String) -> Int64? {
  if token.length() == 0 {
    return None
  }

  let mut start = 0
  let mut sign = 1L
  if token[0] == '+' {
    start = 1
  } else if token[0] == '-' {
    sign = -1L
    start = 1
  }
  if start >= token.length() {
    return None
  }

  let body = token.view(start_offset=start).to_string()

  if body.length() >= 3 &&
    body[0] == '0' &&
    (body[1] == 'x' || body[1] == 'X') {
    let digits = body.view(start_offset=2).to_string()
    match arith_parse_base_digits(digits, 16) {
      Some(v) => return Some(v * sign)
      None => return None
    }
  }

  let mut hash_pos = -1
  for i = 0; i < body.length(); i = i + 1 {
    if body[i] == '#' {
      hash_pos = i
      break
    }
  }
  if hash_pos > 0 {
    let base_text = body.view(start_offset=0, end_offset=hash_pos).to_string()
    let digits = body.view(start_offset=hash_pos + 1).to_string()
    match arith_parse_decimal_str(base_text) {
      Some(base) => {
        if base < 2L || base > 64L {
          return None
        }
        match arith_parse_base_digits(digits, base.to_int()) {
          Some(v) => return Some(v * sign)
          None => return None
        }
      }
      None => return None
    }
  }

  if body.length() > 1 && body[0] == '0' {
    let digits = body.view(start_offset=1).to_string()
    let mut is_octal = true
    for i = 0; i < digits.length(); i = i + 1 {
      let ch = digits[i].to_int().unsafe_to_char()
      if ch < '0' || ch > '7' {
        is_octal = false
        break
      }
    }
    if is_octal {
      match arith_parse_base_digits(digits, 8) {
        Some(v) => return Some(v * sign)
        None => return None
      }
    }
  }

  match arith_parse_decimal_str(body) {
    Some(v) => Some(v * sign)
    None => None
  }
}

fn arith_tokenize(expr : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut i = 0

  while i < expr.length() {
    let ch = expr[i].to_int().unsafe_to_char()

    if arith_is_space(ch) {
      i += 1
      continue
    }

    if arith_is_ident_start(ch) {
      let start = i
      i += 1
      while i < expr.length() && arith_is_ident_char(expr[i].to_int().unsafe_to_char()) {
        i += 1
      }
      tokens.push(expr.view(start_offset=start, end_offset=i).to_string())
      continue
    }

    if arith_is_digit(ch) {
      let start = i
      if i + 1 < expr.length() &&
        ch == '0' &&
        (expr[i + 1] == 'x' || expr[i + 1] == 'X') {
        i += 2
        while i < expr.length() && arith_is_hex_digit(expr[i].to_int().unsafe_to_char()) {
          i += 1
        }
        tokens.push(expr.view(start_offset=start, end_offset=i).to_string())
        continue
      }

      while i < expr.length() && arith_is_digit(expr[i].to_int().unsafe_to_char()) {
        i += 1
      }

      if i < expr.length() && expr[i] == '#' {
        i += 1
        while i < expr.length() && arith_is_base_digit_char(expr[i].to_int().unsafe_to_char()) {
          i += 1
        }
        tokens.push(expr.view(start_offset=start, end_offset=i).to_string())
        continue
      }

      while i < expr.length() && arith_is_ident_char(expr[i].to_int().unsafe_to_char()) {
        i += 1
      }
      tokens.push(expr.view(start_offset=start, end_offset=i).to_string())
      continue
    }

    if i + 2 < expr.length() {
      let a = expr[i].to_int().unsafe_to_char()
      let b = expr[i + 1].to_int().unsafe_to_char()
      let c = expr[i + 2].to_int().unsafe_to_char()
      if a == '<' && b == '<' && c == '=' {
        tokens.push("<<=")
        i += 3
        continue
      }
      if a == '>' && b == '>' && c == '=' {
        tokens.push(">>=")
        i += 3
        continue
      }
    }

    if i + 1 < expr.length() {
      let a = expr[i].to_int().unsafe_to_char()
      let b = expr[i + 1].to_int().unsafe_to_char()
      if (a == '+' && b == '+') ||
        (a == '-' && b == '-') ||
        (a == '&' && b == '&') ||
        (a == '|' && b == '|') ||
        (a == '=' && b == '=') ||
        (a == '!' && b == '=') ||
        (a == '<' && b == '=') ||
        (a == '>' && b == '=') ||
        (a == '+' && b == '=') ||
        (a == '-' && b == '=') ||
        (a == '*' && b == '=') ||
        (a == '/' && b == '=') ||
        (a == '%' && b == '=') ||
        (a == '&' && b == '=') ||
        (a == '|' && b == '=') ||
        (a == '^' && b == '=') ||
        (a == '<' && b == '<') ||
        (a == '>' && b == '>') {
        tokens.push(expr.view(start_offset=i, end_offset=i + 2).to_string())
        i += 2
        continue
      }
    }

    match ch {
      '+' | '-' | '*' | '/' | '%' | '=' | '!' | '~' | '<' | '>' | '&' | '|'
      | '^' | '?' | ':' | ',' | '(' | ')' | '[' | ']' => {
        tokens.push(expr.view(start_offset=i, end_offset=i + 1).to_string())
        i += 1
      }
      _ => {
        // Ignore unsupported characters without failing the whole expression.
        i += 1
      }
    }
  }

  tokens
}

fn arith_is_assignment_op(op : String) -> Bool {
  op == "=" ||
  op == "+=" ||
  op == "-=" ||
  op == "*=" ||
  op == "/=" ||
  op == "%=" ||
  op == "&=" ||
  op == "|=" ||
  op == "^=" ||
  op == "<<=" ||
  op == ">>="
}

fn arith_shift_left(v : Int64, amount : Int64) -> Int64 {
  if amount < 0L {
    v
  } else if amount >= 64L {
    0L
  } else {
    v << amount.to_int()
  }
}

fn arith_shift_right(v : Int64, amount : Int64) -> Int64 {
  if amount < 0L {
    v
  } else if amount >= 64L {
    if v < 0L { -1L } else { 0L }
  } else {
    v >> amount.to_int()
  }
}

