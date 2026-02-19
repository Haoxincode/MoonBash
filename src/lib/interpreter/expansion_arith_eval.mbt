// Shell arithmetic expansion - recursive descent parser and word splitting

fn ExecContext::arith_parse_value_text(self : ExecContext, text : String) -> Int64 {
  let trimmed = arith_trim(text)
  if trimmed.length() == 0 {
    return 0L
  }

  if trimmed.length() >= 2 &&
    trimmed[0] == '(' &&
    trimmed[trimmed.length() - 1] == ')' {
    let inner = trimmed.view(start_offset=1, end_offset=trimmed.length() - 1).to_string()
    let parts = split_by_whitespace(inner)
    if parts.length() == 0 {
      return 0L
    }
    return self.arith_parse_value_text(parts[0])
  }

  match arith_parse_number_literal(trimmed) {
    Some(v) => v
    None => parse_int_str(trimmed)
  }
}

fn ExecContext::arith_get_var_value(self : ExecContext, name : String) -> Int64 {
  let mut current = name
  let mut depth = 0

  while depth < 32 {
    let raw = self.env.get(current).unwrap_or("")
    let trimmed = arith_trim(raw)
    if trimmed.length() == 0 {
      return 0L
    }

    if arith_is_identifier_text(trimmed) && trimmed != current {
      current = trimmed
      depth += 1
      continue
    }

    return self.arith_parse_value_text(trimmed)
  }

  0L
}

fn ExecContext::arith_get_array_elem(
  self : ExecContext,
  name : String,
  index : Int64
) -> Int64 {
  if index < 0L {
    return 0L
  }

  let key = name + "[" + index.to_string() + "]"
  match self.env.get(key) {
    Some(v) => return self.arith_parse_value_text(v)
    None => ()
  }

  let raw = self.env.get(name).unwrap_or("")
  let trimmed = arith_trim(raw)
  if trimmed.length() >= 2 &&
    trimmed[0] == '(' &&
    trimmed[trimmed.length() - 1] == ')' {
    let inner = trimmed.view(start_offset=1, end_offset=trimmed.length() - 1).to_string()
    let parts = split_by_whitespace(inner)
    if index < parts.length().to_int64() {
      return self.arith_parse_value_text(parts[index.to_int()])
    }
  }

  0L
}

fn ExecContext::arith_set_target(
  self : ExecContext,
  target : ArithTarget,
  value : Int64,
  execute : Bool
) -> Unit {
  if not(execute) {
    return
  }

  match target {
    NoTarget => ()
    Var(name) => self.env[name] = value.to_string()
    ArrayElem(name, index) => {
      if index < 0L {
        return
      }
      let key = name + "[" + index.to_string() + "]"
      self.env[key] = value.to_string()
      if index == 0L {
        self.env[name] = value.to_string()
      }
    }
  }
}

fn ExecContext::arith_parse_primary(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  match p.peek() {
    Some(tok) => {
      if tok == "(" {
        ignore(p.advance())
        let result = self.arith_parse_comma(p, execute)
        ignore(p.match_tok(")"))
        return arith_plain(result.value)
      }

      ignore(p.advance())

      if arith_is_identifier_text(tok) {
        if p.match_tok("[") {
          let idx_expr = self.arith_parse_comma(p, execute)
          ignore(p.match_tok("]"))
          let idx = idx_expr.value
          let value = self.arith_get_array_elem(tok, idx)
          return arith_with_target(value, ArrayElem(tok, idx))
        }
        let value = self.arith_get_var_value(tok)
        return arith_with_target(value, Var(tok))
      }

      match arith_parse_number_literal(tok) {
        Some(v) => arith_plain(v)
        None => arith_plain(parse_int_str(tok))
      }
    }
    None => arith_plain(0L)
  }
}

fn ExecContext::arith_parse_postfix(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut value = self.arith_parse_primary(p, execute)

  while true {
    if p.match_tok("++") {
      let old = value.value
      let newv = old + 1L
      self.arith_set_target(value.target, newv, execute)
      value = arith_plain(old)
      continue
    }
    if p.match_tok("--") {
      let old = value.value
      let newv = old - 1L
      self.arith_set_target(value.target, newv, execute)
      value = arith_plain(old)
      continue
    }
    break
  }

  value
}

fn ExecContext::arith_parse_unary(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  match p.peek() {
    Some(op) => {
      if op == "+" || op == "-" || op == "!" || op == "~" || op == "++" || op == "--" {
        ignore(p.advance())
        let operand = self.arith_parse_unary(p, execute)
        match op {
          "+" => arith_plain(operand.value)
          "-" => arith_plain(-operand.value)
          "!" => arith_plain(if operand.value == 0L { 1L } else { 0L })
          "~" => arith_plain(operand.value.lnot())
          "++" => {
            let newv = operand.value + 1L
            match operand.target {
              NoTarget => arith_plain(operand.value)
              _ => {
                self.arith_set_target(operand.target, newv, execute)
                arith_plain(newv)
              }
            }
          }
          "--" => {
            let newv = operand.value - 1L
            match operand.target {
              NoTarget => arith_plain(operand.value)
              _ => {
                self.arith_set_target(operand.target, newv, execute)
                arith_plain(newv)
              }
            }
          }
          _ => arith_plain(operand.value)
        }
      } else {
        self.arith_parse_postfix(p, execute)
      }
    }
    None => self.arith_parse_postfix(p, execute)
  }
}

fn ExecContext::arith_parse_mul(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_unary(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "*" || op == "/" || op == "%" {
          ignore(p.advance())
          let right = self.arith_parse_unary(p, execute)
          let value = match op {
            "*" => left.value * right.value
            "/" => if right.value == 0L { 0L } else { left.value / right.value }
            "%" => if right.value == 0L { 0L } else { left.value % right.value }
            _ => left.value
          }
          left = arith_plain(value)
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_add(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_mul(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "+" || op == "-" {
          ignore(p.advance())
          let right = self.arith_parse_mul(p, execute)
          let value = if op == "+" {
            left.value + right.value
          } else {
            left.value - right.value
          }
          left = arith_plain(value)
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_shift(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_add(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "<<" || op == ">>" {
          ignore(p.advance())
          let right = self.arith_parse_add(p, execute)
          let value = if op == "<<" {
            arith_shift_left(left.value, right.value)
          } else {
            arith_shift_right(left.value, right.value)
          }
          left = arith_plain(value)
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_rel(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_shift(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "<" || op == "<=" || op == ">" || op == ">=" {
          ignore(p.advance())
          let right = self.arith_parse_shift(p, execute)
          let ok = if op == "<" {
            left.value < right.value
          } else if op == "<=" {
            left.value <= right.value
          } else if op == ">" {
            left.value > right.value
          } else {
            left.value >= right.value
          }
          left = arith_plain(if ok { 1L } else { 0L })
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_eq(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_rel(p, execute)

  while true {
    match p.peek() {
      Some(op) => {
        if op == "==" || op == "!=" {
          ignore(p.advance())
          let right = self.arith_parse_rel(p, execute)
          let ok = if op == "==" {
            left.value == right.value
          } else {
            left.value != right.value
          }
          left = arith_plain(if ok { 1L } else { 0L })
        } else {
          break
        }
      }
      None => break
    }
  }

  left
}

fn ExecContext::arith_parse_bitand(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_eq(p, execute)
  while p.match_tok("&") {
    let right = self.arith_parse_eq(p, execute)
    left = arith_plain(left.value.land(right.value))
  }
  left
}

fn ExecContext::arith_parse_bitxor(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_bitand(p, execute)
  while p.match_tok("^") {
    let right = self.arith_parse_bitand(p, execute)
    left = arith_plain(left.value.lxor(right.value))
  }
  left
}

fn ExecContext::arith_parse_bitor(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_bitxor(p, execute)
  while p.match_tok("|") {
    let right = self.arith_parse_bitxor(p, execute)
    left = arith_plain(left.value.lor(right.value))
  }
  left
}

fn ExecContext::arith_parse_logand(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_bitor(p, execute)

  while p.match_tok("&&") {
    if left.value != 0L {
      let right = self.arith_parse_bitor(p, execute)
      left = arith_plain(if right.value != 0L { 1L } else { 0L })
    } else {
      ignore(self.arith_parse_bitor(p, false))
      left = arith_plain(0L)
    }
  }

  left
}

fn ExecContext::arith_parse_logor(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut left = self.arith_parse_logand(p, execute)

  while p.match_tok("||") {
    if left.value != 0L {
      ignore(self.arith_parse_logand(p, false))
      left = arith_plain(1L)
    } else {
      let right = self.arith_parse_logand(p, execute)
      left = arith_plain(if right.value != 0L { 1L } else { 0L })
    }
  }

  left
}

fn ExecContext::arith_parse_ternary(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let cond = self.arith_parse_logor(p, execute)
  if not(p.match_tok("?")) {
    return cond
  }

  if cond.value != 0L {
    let then_v = self.arith_parse_comma(p, execute)
    if p.match_tok(":") {
      ignore(self.arith_parse_ternary(p, false))
    }
    arith_plain(then_v.value)
  } else {
    ignore(self.arith_parse_comma(p, false))
    if p.match_tok(":") {
      let else_v = self.arith_parse_ternary(p, execute)
      arith_plain(else_v.value)
    } else {
      arith_plain(0L)
    }
  }
}

fn ExecContext::arith_parse_assignment(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let left = self.arith_parse_ternary(p, execute)
  let op = match p.peek() {
    Some(v) => v
    None => return left
  }
  if not(arith_is_assignment_op(op)) {
    return left
  }

  ignore(p.advance())
  let right = self.arith_parse_assignment(p, execute)

  let newv = match op {
    "=" => right.value
    "+=" => left.value + right.value
    "-=" => left.value - right.value
    "*=" => left.value * right.value
    "/=" => if right.value == 0L { 0L } else { left.value / right.value }
    "%=" => if right.value == 0L { 0L } else { left.value % right.value }
    "&=" => left.value.land(right.value)
    "|=" => left.value.lor(right.value)
    "^=" => left.value.lxor(right.value)
    "<<=" => arith_shift_left(left.value, right.value)
    ">>=" => arith_shift_right(left.value, right.value)
    _ => right.value
  }

  self.arith_set_target(left.target, newv, execute)
  arith_plain(newv)
}

fn ExecContext::arith_parse_comma(
  self : ExecContext,
  p : ArithParser,
  execute : Bool
) -> ArithValue {
  let mut result = self.arith_parse_assignment(p, execute)
  while p.match_tok(",") {
    result = self.arith_parse_assignment(p, execute)
  }
  result
}

fn arith_is_special_var_char(ch : Char) -> Bool {
  ch == '?' ||
  ch == '!' ||
  ch == '$' ||
  ch == '#' ||
  ch == '@' ||
  ch == '*' ||
  ch == '-'
}

fn ExecContext::arith_expand_dollar_refs(self : ExecContext, raw : String) -> String {
  let out = StringBuilder::new()
  let mut i = 0
  while i < raw.length() {
    let ch = raw[i].to_int().unsafe_to_char()
    if ch == '$' && i + 1 < raw.length() {
      let next = raw[i + 1].to_int().unsafe_to_char()
      if arith_is_ident_start(next) {
        let mut j = i + 2
        while j < raw.length() && arith_is_ident_char(raw[j].to_int().unsafe_to_char()) {
          j += 1
        }
        let name = raw.view(start_offset=i + 1, end_offset=j).to_string()
        out.write_string(self.expand_variable(name))
        i = j
        continue
      }
      if arith_is_digit(next) {
        let mut j = i + 2
        while j < raw.length() && arith_is_digit(raw[j].to_int().unsafe_to_char()) {
          j += 1
        }
        let name = raw.view(start_offset=i + 1, end_offset=j).to_string()
        out.write_string(self.expand_variable(name))
        i = j
        continue
      }
      if arith_is_special_var_char(next) {
        let name = raw.view(start_offset=i + 1, end_offset=i + 2).to_string()
        out.write_string(self.expand_variable(name))
        i += 2
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

fn ExecContext::eval_arith_raw(self : ExecContext, raw : String) -> Int64 {
  let expanded = self.arith_expand_dollar_refs(raw)
  let tokens = arith_tokenize(expanded)
  if tokens.length() == 0 {
    return 0L
  }
  let parser : ArithParser = { tokens, pos: 0 }
  let result = self.arith_parse_comma(parser, true)
  result.value
}

fn ExecContext::eval_arith(self : ExecContext, expr : @ast.ArithExpr) -> Int64 {
  match expr {
    @ast.ArithExpr::Num(n) => n
    @ast.ArithExpr::Var(name) => self.arith_get_var_value(name)
    @ast.ArithExpr::BinOp(op, left, right) => {
      let l = self.eval_arith(left)
      let r = self.eval_arith(right)
      match op {
        @ast.ArithBinOp::Add => l + r
        @ast.ArithBinOp::Sub => l - r
        @ast.ArithBinOp::Mul => l * r
        @ast.ArithBinOp::Div => if r == 0L { 0L } else { l / r }
        @ast.ArithBinOp::Mod => if r == 0L { 0L } else { l % r }
        @ast.ArithBinOp::Eq => if l == r { 1L } else { 0L }
        @ast.ArithBinOp::Ne => if l != r { 1L } else { 0L }
        @ast.ArithBinOp::Lt => if l < r { 1L } else { 0L }
        @ast.ArithBinOp::Le => if l <= r { 1L } else { 0L }
        @ast.ArithBinOp::Gt => if l > r { 1L } else { 0L }
        @ast.ArithBinOp::Ge => if l >= r { 1L } else { 0L }
        @ast.ArithBinOp::LogicalAnd => if l != 0L && r != 0L { 1L } else { 0L }
        @ast.ArithBinOp::LogicalOr => if l != 0L || r != 0L { 1L } else { 0L }
        @ast.ArithBinOp::BitwiseAnd => l.land(r)
        @ast.ArithBinOp::BitwiseOr => l.lor(r)
        @ast.ArithBinOp::BitwiseXor => l.lxor(r)
        @ast.ArithBinOp::ShiftLeft => arith_shift_left(l, r)
        @ast.ArithBinOp::ShiftRight => arith_shift_right(l, r)
        @ast.ArithBinOp::Pow => int_pow(l, r)
      }
    }
    @ast.ArithExpr::UnaryOp(op, operand) => {
      let v = self.eval_arith(operand)
      match op {
        @ast.ArithUnaryOp::Negate => -v
        @ast.ArithUnaryOp::LogicalNot => if v == 0L { 1L } else { 0L }
        @ast.ArithUnaryOp::BitwiseNot => v.lnot()
        @ast.ArithUnaryOp::PreIncr | @ast.ArithUnaryOp::PostIncr => v + 1L
        @ast.ArithUnaryOp::PreDecr | @ast.ArithUnaryOp::PostDecr => v - 1L
      }
    }
    @ast.ArithExpr::Assign(name, value_expr) => {
      let v = self.eval_arith(value_expr)
      self.env[name] = v.to_string()
      v
    }
    @ast.ArithExpr::Ternary(cond, then_expr, else_expr) => {
      let c = self.eval_arith(cond)
      if c != 0L {
        self.eval_arith(then_expr)
      } else {
        self.eval_arith(else_expr)
      }
    }
    @ast.ArithExpr::Raw(raw) => self.eval_arith_raw(raw)
  }
}

// ============================================================================
// Word Splitting
// ============================================================================

fn ExecContext::word_split(
  self : ExecContext,
  s : String
) -> Array[String] {
  if s.length() == 0 {
    return [""]
  }
  let ifs = self.env.get("IFS").unwrap_or(" \t\n")
  if ifs.length() == 0 {
    return [s]
  }
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i].to_int().unsafe_to_char()
    if is_ifs_char(ch, ifs) {
      let word = buf.to_string()
      if word.length() > 0 {
        result.push(word)
        buf.reset()
      }
    } else {
      buf.write_char(ch)
    }
  }
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    result.push(remaining)
  }
  if result.length() == 0 {
    return [s]
  }
  result
}

fn is_ifs_char(ch : Char, ifs : String) -> Bool {
  for i = 0; i < ifs.length(); i = i + 1 {
    if ifs[i].to_int().unsafe_to_char() == ch {
      return true
    }
  }
  false
}

