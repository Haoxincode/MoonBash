/**
 * Re-export Bash class and types for test usage.
 * Tests import from this file: import { Bash } from "../Bash.js";
 */
export { Bash, exec, Sandbox } from "../src/wrapper/index.ts";
export type { ExecResult, BashOptions, FileSystem } from "../src/wrapper/types.ts";
