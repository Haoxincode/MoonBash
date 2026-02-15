// MoonBash Interpreter - Builtin Dispatch
// Split from builtins_core.mbt for maintainability.

fn ExecContext::run_builtin(
  self : ExecContext,
  name : String,
  args : Array[String]
) -> Bool {
  match name {
    "export" => {
      self.builtin_export(args)
      true
    }
    "unset" => {
      self.builtin_unset(args)
      true
    }
    "set" => {
      self.builtin_set(args)
      true
    }
    "shift" => {
      self.builtin_shift(args)
      true
    }
    "exit" => {
      self.builtin_exit(args)
      true
    }
    "return" => {
      self.builtin_return(args)
      true
    }
    "break" => {
      self.builtin_break(args)
      true
    }
    "continue" => {
      self.builtin_continue(args)
      true
    }
    "read" => {
      self.builtin_read(args)
      true
    }
    "test" | "[" => {
      self.builtin_test(args)
      true
    }
    "printf" => {
      self.builtin_printf(args)
      true
    }
    "eval" => {
      self.builtin_eval(args)
      true
    }
    "source" | "." => {
      self.builtin_source(args)
      true
    }
    "local" => {
      self.builtin_local(args)
      true
    }
    "declare" | "typeset" => {
      self.builtin_declare(args)
      true
    }
    ":" => {
      self.exit_code = 0
      true
    }
    "type" => {
      self.builtin_type(args)
      true
    }
    "command" => {
      self.builtin_command(args)
      true
    }
    "basename" => {
      self.builtin_basename(args)
      true
    }
    "dirname" => {
      self.builtin_dirname(args)
      true
    }
    "seq" => {
      self.builtin_seq(args)
      true
    }
    "rev" => {
      self.builtin_rev(args)
      true
    }
    "nl" => {
      self.builtin_nl(args)
      true
    }
    "fold" => {
      self.builtin_fold(args)
      true
    }
    "expand" => {
      self.builtin_expand(args)
      true
    }
    "unexpand" => {
      self.builtin_unexpand(args)
      true
    }
    "paste" => {
      self.builtin_paste(args)
      true
    }
    "column" => {
      self.builtin_column(args)
      true
    }
    "join" => {
      self.builtin_join(args)
      true
    }
    "tr" => {
      self.builtin_tr(args)
      true
    }
    "sort" => {
      self.builtin_sort(args)
      true
    }
    "uniq" => {
      self.builtin_uniq(args)
      true
    }
    "cut" => {
      self.builtin_cut(args)
      true
    }
    "tee" => {
      self.builtin_tee(args)
      true
    }
    "sed" => {
      self.builtin_sed(args)
      true
    }
    "grep" => {
      self.builtin_grep(args)
      true
    }
    "egrep" => {
      let grep_args : Array[String] = ["-E"]
      for arg in args {
        grep_args.push(arg)
      }
      self.builtin_grep(grep_args)
      true
    }
    "fgrep" => {
      let grep_args : Array[String] = ["-F"]
      for arg in args {
        grep_args.push(arg)
      }
      self.builtin_grep(grep_args)
      true
    }
    "rg" => {
      let grep_args : Array[String] = ["-E"]
      for arg in args {
        grep_args.push(arg)
      }
      self.builtin_grep(grep_args)
      true
    }
    "xargs" => {
      self.builtin_xargs(args)
      true
    }
    "date" => {
      self.builtin_date(args)
      true
    }
    "env" | "printenv" => {
      self.builtin_env(args)
      true
    }
    "which" => {
      self.builtin_which(args)
      true
    }
    _ => false
  }
}
