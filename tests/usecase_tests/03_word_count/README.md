# Word count

Build and run from the repository root:

```sh
zig build
./zig-out/bin/argi build tests/usecase_tests/03_word_count
./tests/usecase_tests/03_word_count/build/output path/to/directory 1048576
```

The optional second argument sets the maximum bytes accepted per file; it
otherwise defaults to 1 MiB. The directory's immediate regular files are read
with an initialized 8 KiB scratch buffer and the per-file byte limit.
Subdirectories and other entry kinds are skipped.
Metadata follows native link rules, so this is not a sandbox or a recursive
walker. Files may change between metadata and opening.

Every file must contain valid UTF-8. Words are maximal byte runs separated by
ASCII whitespace (space, tab, CR, LF, vertical tab, form feed). Case and
punctuation are preserved. Unicode normalization, language-specific tokenizing,
and non-ASCII whitespace classification are outside this example's contract.
Output is `count`, a tab, and the original word, one entry per line; table order
is unspecified. Nothing is printed until all files have been counted. A read,
validation, size, allocation, or count overflow error fails the program and
releases accumulated owners. The reusable counting functions can retain counts
from earlier files on error; a single invalid UTF-8 input is validated before
any count changes.

The library receives explicit filesystem and allocator capabilities. The CLI
uses inferred Errable reasons, a buffered output writer with a checked deferred
flush, owning strings and hash entries, checked count increments, and borrowed
iteration. Files are explicitly closed before their text is counted; file errors
include their path. It never acquires safe references from native file handles.

Whitespace tokens use ordinary `for` iteration. Hash lookup borrows each token
as a StringView; only a new word allocates an owning key. Directory entry paths
use the standard `join_views` operation, which recognizes the target's native
separators and avoids adding a duplicate separator. It does not normalize paths
or resolve them against the filesystem.
