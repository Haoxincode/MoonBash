/**
 * Compatibility command-flag metadata for fuzz generators.
 */

const COMMAND_FUZZ_INFOS = [
  {
    name: "echo",
    flags: [{ flag: "-n", type: "boolean" }],
    needsArgs: true,
    minArgs: 1,
  },
  {
    name: "grep",
    flags: [
      { flag: "-i", type: "boolean" },
      { flag: "-n", type: "boolean" },
      { flag: "-e", type: "value", valueHint: "pattern" },
    ],
    needsArgs: true,
    minArgs: 1,
    stdinType: "text",
  },
  {
    name: "sed",
    flags: [
      { flag: "-n", type: "boolean" },
      { flag: "-e", type: "value", valueHint: "pattern" },
    ],
    needsArgs: true,
    minArgs: 1,
    stdinType: "text",
  },
  {
    name: "awk",
    flags: [{ flag: "-F", type: "value", valueHint: "delimiter" }],
    needsArgs: true,
    minArgs: 1,
    stdinType: "text",
  },
  {
    name: "jq",
    flags: [{ flag: "-c", type: "boolean" }],
    needsArgs: true,
    minArgs: 1,
    stdinType: "json",
  },
  {
    name: "sort",
    flags: [{ flag: "-r", type: "boolean" }],
    needsFiles: true,
  },
];

export function getAllCommandFuzzInfo() {
  return COMMAND_FUZZ_INFOS.map((info) => ({
    ...info,
    flags: info.flags.map((flag) => ({ ...flag })),
  }));
}

