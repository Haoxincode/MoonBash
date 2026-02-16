/**
 * Compatibility in-memory fs used by imported sandbox tests.
 * It only implements the subset required by those tests.
 */

function normalizePath(path) {
  const raw = typeof path === "string" ? path : String(path ?? "");
  if (raw.startsWith("/")) {
    return raw;
  }
  return `/${raw}`;
}

export class InMemoryFs {
  constructor(initialFiles = {}) {
    this.files = new Map();
    for (const [path, content] of Object.entries(initialFiles)) {
      this.files.set(normalizePath(path), String(content ?? ""));
    }
  }

  async writeFile(path, content) {
    this.files.set(normalizePath(path), String(content ?? ""));
  }

  async readFile(path) {
    const normalized = normalizePath(path);
    if (!this.files.has(normalized)) {
      throw new Error(`No such file: ${normalized}`);
    }
    return this.files.get(normalized);
  }

  async exists(path) {
    return this.files.has(normalizePath(path));
  }

  __moon_bash_snapshot() {
    const out = {};
    for (const [path, content] of this.files.entries()) {
      out[path] = content;
    }
    return out;
  }
}

