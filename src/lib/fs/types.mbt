// MoonBash Filesystem Types

pub(all) enum FsEntry {
  File(FileData)
  Directory(DirData)
  Symlink(SymlinkData)
}

pub(all) struct FileData {
  mut content : String
  mut mode : Int
  mut mtime : Int64
}

pub(all) struct DirData {
  mut mode : Int
  mut mtime : Int64
}

pub(all) struct SymlinkData {
  target : String
  mut mode : Int
  mut mtime : Int64
}

pub(all) struct FsStat {
  is_file : Bool
  is_directory : Bool
  is_symlink : Bool
  size : Int
  mode : Int
  mtime : Int64
} derive(Show)

pub(all) struct DirentEntry {
  name : String
  entry_type : EntryType
} derive(Show)

pub(all) enum EntryType {
  FileType
  DirectoryType
  SymlinkType
} derive(Show)

pub suberror FsError {
  FsError(String)
}
