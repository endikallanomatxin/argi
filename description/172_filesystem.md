# Filesystem operations

`create_directory(.path, .self)` creates one directory, and
`remove_directory(.path, .self)` removes an empty directory. Paths are bounded
`StringView` inputs; `.self` defaults to reached `file_sys`. Empty paths and
embedded NUL bytes are rejected as `invalid_path`. POSIX paths use native bytes;
Windows paths are converted from UTF-8 to wide native paths.

`metadata(.path, .self)` returns `FileMetadata` with `.kind` (`file`, `directory`,
`other`), native `.size` in bytes, and `.modified` as a `UnixTimestamp`. A directory's
size is native metadata, not the size of its descendants. Native platform rules
apply to links and special files. Existence checks are observations, not promises
that a later open will succeed.

These operations distinguish `path_not_found`, `permission_denied`,
`already_exists`, `not_a_directory`, `invalid_path`, and `out_of_memory` where
native errors provide those facts. Other failures report `filesystem_failed`.
Directories are not recursively created or removed. POSIX creation uses mode
0700 subject to the process umask; Windows inherits its parent's access policy.

## Enumeration

`Directory(.path, .self)` owns a native enumeration handle and borrows its
filesystem capability. Checked `next(.self, .allocator)` returns an optional
owning `DirectoryEntry` with `.name: String`. Names exclude `.` and `..` and
contain only the immediate entry name. The order is native and unspecified.
Each name is copied and can outlive the directory owner. Query metadata using
an explicitly joined path when needed.

Enumeration remains fallible rather than pretending to satisfy an infallible
iterator contract. It is not a snapshot of concurrent directory changes.
Allocation failure after native advancement consumes that entry. End is sticky:
subsequent calls return none. Cleanup closes the native handle exactly once;
copying a Directory or using it after cleanup is rejected.

## File positions

`seek(.self, .offset, .origin)` accepts a signed Int64 offset and `SeekOrigin`
(`start`, `current`, `end`), returning the resulting UInt64 byte position.
`position(.self)` queries the current position. These operations fail with
`stream_seek_failed` for unsupported streams, invalid positions, or closed files.
A successful seek follows native stdio rules, including resetting EOF.

`truncate(.self, .size)` changes the file length after flushing stdio writes,
and reports `stream_truncate_failed` on failure. It requires a suitable writable
file. It leaves the cursor position unchanged; extensions and sparse ranges
follow the native filesystem. Existing buffered wrappers must not retain stale
read-ahead data across a seek or truncate on their underlying file.

## Temporary directories

`TemporaryDirectory(.parent, .prefix, .self, .allocator)` exclusively creates a
new directory in an explicit parent; prefix defaults to `argi-`. Prefixes are
bounded to 32 bytes and cannot contain NUL, slash, backslash, or colon. POSIX uses
`mkdtemp`; Windows uses system entropy and exclusive directory creation with
bounded collision retries. No existence-check-then-create sequence is used.

`path(.self)` returns a borrowed path view. `close(.self)` removes the empty
directory and is idempotent after success. Failure leaves the owner able to
retry. Automatic cleanup attempts to remove the directory and releases its
private native metadata and owned path even if removal fails.

Callers must remove their created children before cleanup. Cleanup never
recursively deletes user data; a nonempty directory remains on disk. A retained
path view borrows the owning String, not a promise that the directory still
exists. No native handle or copied address grants safe-reference validity or
an allocation receipt.
