/**
 * Compatibility lexer shim for imported just-bash tests.
 * This only supports the small surface used by security limit tests.
 */

export class Lexer {
  constructor(source) {
    this.source = typeof source === "string" ? source : String(source ?? "");
  }

  tokenize() {
    return this.source.split(/\s+/).filter((token) => token.length > 0);
  }
}

