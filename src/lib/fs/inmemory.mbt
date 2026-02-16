// MoonBash InMemoryFs - HashMap-based Virtual Filesystem

pub(all) struct InMemoryFs {
  entries : Map[String, FsEntry]
}

/// Create a new InMemoryFs with default directory layout.
pub fn InMemoryFs::new() -> InMemoryFs {
  let entries : Map[String, FsEntry] = {}
  let now : Int64 = 0L
  entries["/"] = Directory({ mode: 0o755, mtime: now })
  entries["/home"] = Directory({ mode: 0o755, mtime: now })
  entries["/home/user"] = Directory({ mode: 0o755, mtime: now })
  entries["/bin"] = Directory({ mode: 0o755, mtime: now })
  entries["/usr"] = Directory({ mode: 0o755, mtime: now })
  entries["/usr/bin"] = Directory({ mode: 0o755, mtime: now })
  entries["/tmp"] = Directory({ mode: 0o1777, mtime: now })
  { entries, }
}

/// Follow symlinks to resolve the final path. Max depth prevents loops.
fn InMemoryFs::resolve_symlinks(
  self : InMemoryFs,
  path : String,
  max_depth~ : Int = 40
) -> String raise FsError {
  let norm = normalize_path(path)
  let mut current = norm
  for i = 0; i < max_depth; i = i + 1 {
    match self.entries.get(current) {
      Some(Symlink(data)) => {
        let target = data.target
        current = if target.length() > 0 && target[0] == '/' {
          normalize_path(target)
        } else {
          normalize_path(parent_path(current) + "/" + target)
        }
      }
      _ => return current
    }
  }
  raise FsError("Too many levels of symbolic links: " + path)
}

/// Ensure all parent directories exist for a given path.
fn InMemoryFs::ensure_parent_dirs(
  self : InMemoryFs,
  path : String
) -> Unit raise FsError {
  let parent = parent_path(path)
  if parent == path {
    return
  }
  match self.entries.get(parent) {
    Some(Directory(_)) => return
    Some(File(_)) =>
      raise FsError("Not a directory: " + parent)
    Some(Symlink(_)) => {
      let resolved = self.resolve_symlinks(parent)
      match self.entries.get(resolved) {
        Some(Directory(_)) => return
        _ => raise FsError("Not a directory: " + parent)
      }
    }
    None => {
      self.ensure_parent_dirs(parent)
      let now : Int64 = 0L
      self.entries[parent] = Directory({ mode: 0o755, mtime: now })
    }
  }
}

/// Read a file's content. Follows symlinks.
pub fn InMemoryFs::read_file(
  self : InMemoryFs,
  path : String
) -> String raise FsError {
  let norm = normalize_path(path)
  let resolved = self.resolve_symlinks(norm)
  match self.entries.get(resolved) {
    Some(File(data)) => data.content
    Some(Directory(_)) => raise FsError("Is a directory: " + path)
    Some(Symlink(_)) => raise FsError("Dangling symlink: " + path)
    None => raise FsError("No such file or directory: " + path)
  }
}

/// Write content to a file. Auto-creates parent directories.
pub fn InMemoryFs::write_file(
  self : InMemoryFs,
  path : String,
  content : String
) -> Unit raise FsError {
  let norm = normalize_path(path)
  let target = try {
    self.resolve_symlinks(norm)
  } catch {
    _ => norm
  }
  match self.entries.get(target) {
    Some(Directory(_)) => raise FsError("Is a directory: " + path)
    _ => ()
  }
  self.ensure_parent_dirs(target)
  let now : Int64 = 0L
  match self.entries.get(target) {
    Some(File(data)) => {
      data.content = content
      data.mtime = now
    }
    _ =>
      self.entries[target] = File({ content, mode: 0o644, mtime: now })
  }
}

/// Append content to a file. Creates the file if it doesn't exist.
pub fn InMemoryFs::append_file(
  self : InMemoryFs,
  path : String,
  content : String
) -> Unit raise FsError {
  let norm = normalize_path(path)
  let target = try {
    self.resolve_symlinks(norm)
  } catch {
    _ => norm
  }
  match self.entries.get(target) {
    Some(File(data)) => {
      data.content = data.content + content
      let now : Int64 = 0L
      data.mtime = now
    }
    Some(Directory(_)) => raise FsError("Is a directory: " + path)
    _ => {
      self.ensure_parent_dirs(target)
      let now : Int64 = 0L
      self.entries[target] = File({ content, mode: 0o644, mtime: now })
    }
  }
}

/// Check if a path exists (does not follow symlinks for the final component).
pub fn InMemoryFs::exists(self : InMemoryFs, path : String) -> Bool {
  let norm = try {
    normalize_path(path)
  } catch {
    _ => return false
  }
  self.entries.contains(norm)
}

/// Get file status information.
pub fn InMemoryFs::stat(
  self : InMemoryFs,
  path : String
) -> FsStat raise FsError {
  let norm = normalize_path(path)
  match self.entries.get(norm) {
    Some(File(data)) =>
      {
        is_file: true,
        is_directory: false,
        is_symlink: false,
        size: data.content.length(),
        mode: data.mode,
        mtime: data.mtime,
      }
    Some(Directory(data)) =>
      {
        is_file: false,
        is_directory: true,
        is_symlink: false,
        size: 0,
        mode: data.mode,
        mtime: data.mtime,
      }
    Some(Symlink(data)) =>
      {
        is_file: false,
        is_directory: false,
        is_symlink: true,
        size: data.target.length(),
        mode: data.mode,
        mtime: data.mtime,
      }
    None => raise FsError("No such file or directory: " + path)
  }
}

/// List immediate children of a directory.
pub fn InMemoryFs::readdir(
  self : InMemoryFs,
  path : String
) -> Array[DirentEntry] raise FsError {
  let norm = normalize_path(path)
  let resolved = self.resolve_symlinks(norm)
  match self.entries.get(resolved) {
    Some(Directory(_)) => ()
    Some(_) => raise FsError("Not a directory: " + path)
    None => raise FsError("No such file or directory: " + path)
  }
  let result : Array[DirentEntry] = []
  let prefix = if resolved == "/" { "/" } else { resolved + "/" }
  let prefix_len = prefix.length()
  self.entries.each(fn(key, value) {
    if key.length() > prefix_len && starts_with(key, prefix) {
      let rest = substr(key, prefix_len, key.length())
      if not(contains_char(rest, '/')) {
        let entry_type = match value {
          File(_) => FileType
          Directory(_) => DirectoryType
          Symlink(_) => SymlinkType
        }
        result.push({ name: rest, entry_type })
      }
    }
  })
  result
}

/// Create a directory. With recursive=true, creates all intermediate dirs.
pub fn InMemoryFs::mkdir(
  self : InMemoryFs,
  path : String,
  recursive~ : Bool = false
) -> Unit raise FsError {
  let norm = normalize_path(path)
  if norm == "/" {
    if recursive {
      return
    }
    raise FsError("Already exists: /")
  }
  if recursive {
    self.mkdir_recursive(norm)
  } else {
    let parent = parent_path(norm)
    match self.entries.get(parent) {
      Some(Directory(_)) => ()
      Some(_) => raise FsError("Not a directory: " + parent)
      None => raise FsError("No such file or directory: " + parent)
    }
    match self.entries.get(norm) {
      Some(_) => raise FsError("Already exists: " + path)
      None => {
        let now : Int64 = 0L
        self.entries[norm] = Directory({ mode: 0o755, mtime: now })
      }
    }
  }
}

/// Helper for recursive mkdir.
fn InMemoryFs::mkdir_recursive(
  self : InMemoryFs,
  path : String
) -> Unit raise FsError {
  match self.entries.get(path) {
    Some(Directory(_)) => return
    Some(_) => raise FsError("Not a directory: " + path)
    None => {
      let parent = parent_path(path)
      if parent != path {
        self.mkdir_recursive(parent)
      }
      let now : Int64 = 0L
      self.entries[path] = Directory({ mode: 0o755, mtime: now })
    }
  }
}

/// Remove a file or directory.
pub fn InMemoryFs::rm(
  self : InMemoryFs,
  path : String,
  recursive~ : Bool = false,
  force~ : Bool = false
) -> Unit raise FsError {
  let norm = normalize_path(path)
  if norm == "/" {
    if recursive {
      let keys_to_remove : Array[String] = []
      self.entries.each(fn(key, _value) {
        if key != "/" {
          keys_to_remove.push(key)
        }
      })
      for key in keys_to_remove {
        self.entries.remove(key)
      }
      return
    }
    raise FsError("Cannot remove root directory")
  }
  match self.entries.get(norm) {
    None => {
      if force {
        return
      }
      raise FsError("No such file or directory: " + path)
    }
    Some(Directory(_)) => {
      if not(recursive) {
        let prefix = norm + "/"
        let mut has_children = false
        self.entries.each(fn(key, _value) {
          if starts_with(key, prefix) {
            has_children = true
          }
        })
        if has_children {
          raise FsError("Directory not empty: " + path)
        }
        self.entries.remove(norm)
      } else {
        let prefix = norm + "/"
        let keys_to_remove : Array[String] = []
        self.entries.each(fn(key, _value) {
          if key == norm || starts_with(key, prefix) {
            keys_to_remove.push(key)
          }
        })
        for key in keys_to_remove {
          self.entries.remove(key)
        }
      }
    }
    Some(_) => {
      self.entries.remove(norm)
    }
  }
}

/// Copy a file or directory.
pub fn InMemoryFs::cp(
  self : InMemoryFs,
  src : String,
  dst : String,
  recursive~ : Bool = false
) -> Unit raise FsError {
  let src_norm = normalize_path(src)
  let dst_norm = normalize_path(dst)
  let src_resolved = self.resolve_symlinks(src_norm)
  match self.entries.get(src_resolved) {
    None => raise FsError("No such file or directory: " + src)
    Some(File(data)) => {
      let final_dst = match self.entries.get(dst_norm) {
        Some(Directory(_)) => dst_norm + "/" + basename(src_norm)
        _ => dst_norm
      }
      self.ensure_parent_dirs(final_dst)
      let now : Int64 = 0L
      self.entries[final_dst] = File(
        { content: data.content, mode: data.mode, mtime: now },
      )
    }
    Some(Directory(_)) => {
      if not(recursive) {
        raise FsError("Is a directory (use recursive): " + src)
      }
      let final_dst = match self.entries.get(dst_norm) {
        Some(Directory(_)) => dst_norm + "/" + basename(src_norm)
        _ => dst_norm
      }
      let prefix = src_resolved + "/"
      let entries_to_copy : Array[(String, FsEntry)] = []
      entries_to_copy.push(
        (src_resolved, Directory({ mode: 0o755, mtime: 0L })),
      )
      self.entries.each(fn(key, value) {
        if starts_with(key, prefix) {
          entries_to_copy.push((key, value))
        }
      })
      let now : Int64 = 0L
      for entry in entries_to_copy {
        let (old_path, old_entry) = entry
        let relative = substr(
          old_path, src_resolved.length(), old_path.length(),
        )
        let new_path = final_dst + relative
        self.ensure_parent_dirs(new_path)
        match old_entry {
          File(fdata) =>
            self.entries[new_path] = File(
              { content: fdata.content, mode: fdata.mode, mtime: now },
            )
          Directory(ddata) =>
            self.entries[new_path] = Directory(
              { mode: ddata.mode, mtime: now },
            )
          Symlink(sdata) =>
            self.entries[new_path] = Symlink(
              { target: sdata.target, mode: sdata.mode, mtime: now },
            )
        }
      }
    }
    Some(Symlink(_)) =>
      raise FsError("Dangling symlink: " + src)
  }
}

/// Move (rename) a file or directory.
pub fn InMemoryFs::mv(
  self : InMemoryFs,
  src : String,
  dst : String
) -> Unit raise FsError {
  let src_norm = normalize_path(src)
  let dst_norm = normalize_path(dst)
  guard self.entries.contains(src_norm) else {
    raise FsError("No such file or directory: " + src)
  }
  let final_dst = match self.entries.get(dst_norm) {
    Some(Directory(_)) => dst_norm + "/" + basename(src_norm)
    _ => dst_norm
  }
  self.ensure_parent_dirs(final_dst)
  match self.entries.get(src_norm) {
    Some(Directory(_)) => {
      let prefix = src_norm + "/"
      let to_move : Array[(String, FsEntry)] = []
      self.entries.each(fn(key, value) {
        if key == src_norm || starts_with(key, prefix) {
          to_move.push((key, value))
        }
      })
      for entry in to_move {
        let (old_path, old_entry) = entry
        let relative = substr(old_path, src_norm.length(), old_path.length())
        let new_path = final_dst + relative
        self.entries[new_path] = old_entry
        self.entries.remove(old_path)
      }
    }
    Some(entry) => {
      self.entries[final_dst] = entry
      self.entries.remove(src_norm)
    }
    None => raise FsError("No such file or directory: " + src)
  }
}

/// Create a symbolic link.
pub fn InMemoryFs::symlink(
  self : InMemoryFs,
  target : String,
  link_path : String
) -> Unit raise FsError {
  let norm = normalize_path(link_path)
  match self.entries.get(norm) {
    Some(_) => raise FsError("Already exists: " + link_path)
    None => {
      self.ensure_parent_dirs(norm)
      let now : Int64 = 0L
      self.entries[norm] = Symlink({ target, mode: 0o777, mtime: now })
    }
  }
}

/// Read the target of a symbolic link (does not follow).
pub fn InMemoryFs::readlink(
  self : InMemoryFs,
  path : String
) -> String raise FsError {
  let norm = normalize_path(path)
  match self.entries.get(norm) {
    Some(Symlink(data)) => data.target
    Some(_) => raise FsError("Not a symbolic link: " + path)
    None => raise FsError("No such file or directory: " + path)
  }
}

/// Change file permissions.
pub fn InMemoryFs::chmod(
  self : InMemoryFs,
  path : String,
  mode : Int
) -> Unit raise FsError {
  let norm = normalize_path(path)
  let resolved = self.resolve_symlinks(norm)
  match self.entries.get(resolved) {
    Some(File(data)) => data.mode = mode
    Some(Directory(data)) => data.mode = mode
    Some(Symlink(data)) => data.mode = mode
    None => raise FsError("No such file or directory: " + path)
  }
}

/// Snapshot all filesystem entries as (path, kind, data) tuples.
/// kind: "f" = file (data is content), "d" = directory, "l" = symlink (data is target)
pub fn InMemoryFs::snapshot_entries(
  self : InMemoryFs
) -> Array[(String, String, String)] {
  let entries : Array[(String, String, String)] = []
  self.entries.each(fn(path, entry) {
    match entry {
      File(data) => entries.push((path, "f", data.content))
      Directory(_) => entries.push((path, "d", ""))
      Symlink(data) => entries.push((path, "l", data.target))
    }
  })
  // Deterministic order for stable JSON snapshots.
  entries.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  entries
}

// String utility helpers

/// Check if string starts with a given prefix.
fn starts_with(s : String, prefix : String) -> Bool {
  if prefix.length() > s.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if s[i] != prefix[i] {
      return false
    }
  }
  true
}

/// Check if a string contains a slash character.
fn contains_char(s : String, c : Char) -> Bool {
  let code = c.to_int().to_uint16()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == code {
      return true
    }
  }
  false
}
