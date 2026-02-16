/**
 * Compatibility parser shim for imported just-bash tests.
 * It provides depth guards and a minimal AST shape.
 */

const MAX_PARSER_NESTING_DEPTH = 100;

function throwDepthError() {
  throw new Error("Maximum parser nesting depth exceeded");
}

function trackParenDepth(script) {
  let depth = 0;
  for (let i = 0; i < script.length; i += 1) {
    const ch = script[i];
    if (ch === "(") {
      depth += 1;
      if (depth > MAX_PARSER_NESTING_DEPTH) {
        throwDepthError();
      }
    } else if (ch === ")" && depth > 0) {
      depth -= 1;
    }
  }
}

function trackKeywordDepth(script) {
  let ifDepth = 0;
  let loopDepth = 0;
  const lines = script.replace(/\r/g, "").split("\n");
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.length === 0 || line.startsWith("#")) {
      continue;
    }

    if (/^if\b/.test(line) && /\bthen\b/.test(line)) {
      ifDepth += 1;
      if (ifDepth > MAX_PARSER_NESTING_DEPTH) {
        throwDepthError();
      }
    }
    if (/^while\b/.test(line) && /\bdo\b/.test(line)) {
      loopDepth += 1;
      if (loopDepth > MAX_PARSER_NESTING_DEPTH) {
        throwDepthError();
      }
    }
    if (/^fi\b/.test(line) && ifDepth > 0) {
      ifDepth -= 1;
    }
    if (/^done\b/.test(line) && loopDepth > 0) {
      loopDepth -= 1;
    }
  }
}

function validateDepth(script) {
  trackParenDepth(script);
  trackKeywordDepth(script);
}

function makeAst(script) {
  const trimmed = script.trim();
  return {
    statements: trimmed.length === 0 ? [] : [{ type: "SimpleCommand", text: trimmed }],
  };
}

export function parse(script) {
  const text = typeof script === "string" ? script : String(script ?? "");
  validateDepth(text);
  return makeAst(text);
}

export class Parser {
  parse(script) {
    return parse(script);
  }

  parseTokens(tokens) {
    const source = Array.isArray(tokens) ? tokens.join(" ") : String(tokens ?? "");
    return parse(source);
  }
}

