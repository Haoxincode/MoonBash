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
    // File system commands (file_ops_ext.mbt)
    "rmdir" => Some(cmd_rmdir)
    "stat" => Some(cmd_stat)
    "file" => Some(cmd_file)
    "tree" => Some(cmd_tree)
    "du" => Some(cmd_du)
    "chmod" => Some(cmd_chmod)
    "ln" => Some(cmd_ln)
    "readlink" => Some(cmd_readlink)
    // Text/data commands (text_data_ext.mbt)
    "diff" => Some(cmd_diff)
    "cmp" => Some(cmd_cmp)
    "comm" => Some(cmd_comm)
    "base64" => Some(cmd_base64)
    "expr" => Some(cmd_expr)
    "yq" => Some(cmd_yq)
    "xan" => Some(cmd_xan)
    "csvlook" => Some(cmd_csvlook)
    // Hash commands (hash.mbt)
    "md5sum" => Some(cmd_md5sum)
    "sha1sum" => Some(cmd_sha1sum)
    "sha256sum" => Some(cmd_sha256sum)
    // Compression commands (compress.mbt)
    "gzip" => Some(cmd_gzip)
    "gunzip" => Some(cmd_gunzip)
    "zcat" => Some(cmd_zcat)
    _ => None
  }
}
