# Word count

Build and run from the repository root:

```sh
zig build
./zig-out/bin/argi build tests/usecase_tests/03_word_count
./tests/usecase_tests/03_word_count/build/output path/to/directory 1048576
```

The optional second argument sets the maximum bytes accepted per file; it
otherwise defaults to 1 MiB. The directory's immediate regular files are read
with bounded scratch storage. Subdirectories and other entry kinds are skipped.
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
uses initialized caller scratch, owning strings and hash entries, checked count
increments, and borrowed iteration. It never acquires safe references from
native file handles.

This consumer exposes two remaining opportunities: query/update owning String
keys using StringView without allocating replacement keys, and portable bounded
path joining. Its current path join accepts the example's explicit directory
path and native enumeration names and inserts `/`, supported by the selected
filesystem adapters. It intentionally does not promise path normalization.
