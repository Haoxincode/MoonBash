// MoonBash Command Registry
// Maps command names to their implementation functions.

pub(all) struct CommandContext {
  args : Array[String]
  stdin_content : String
  cwd : String
  env : Map[String, String]
  fs : @fs.InMemoryFs
}

/// Look up a command implementation by name.
pub fn find_command(
  name : String
) -> ((CommandContext) -> @ast.ExecResult)? {
  match name {
    "echo" => Some(cmd_echo)
    "cat" => Some(cmd_cat)
    "cd" => Some(cmd_cd)
    "pwd" => Some(cmd_pwd)
    "ls" => Some(cmd_ls)
    "mkdir" => Some(cmd_mkdir)
    "rm" => Some(cmd_rm)
    "cp" => Some(cmd_cp)
    "mv" => Some(cmd_mv)
    "touch" => Some(cmd_touch)
    "find" => Some(cmd_find)
    "head" => Some(cmd_head)
    "tail" => Some(cmd_tail)
    "wc" => Some(cmd_wc)
    "strings" => Some(cmd_strings)
    "split" => Some(cmd_split)
    "tar" => Some(cmd_tar)
    "awk" => Some(cmd_awk)
    "jq" => Some(cmd_jq)
    "true" => Some(cmd_true)
    "false" => Some(cmd_false)
    _ => None
  }
}
