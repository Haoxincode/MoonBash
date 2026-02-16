/**
 * Compatibility error exports for imported just-bash tests.
 */

export class ExecutionLimitError extends Error {
  static EXIT_CODE = 126;

  constructor(message = "execution limit exceeded") {
    super(message);
    this.name = "ExecutionLimitError";
  }
}

