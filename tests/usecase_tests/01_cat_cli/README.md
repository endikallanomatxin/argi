# Streaming cat CLI

Build with `zig build`, then `./zig-out/bin/argi build tests/usecase_tests/01_cat_cli`.
Run `tests/usecase_tests/01_cat_cli/build/output [FILE...]` (add `.exe` on Windows).

The program concatenates files in argument order. With no files it reads standard
input; `-` reads standard input at that position. Use `--` before filenames that
start with a hyphen. `-h` or `--help` prints help without opening any files.

Copying preserves binary bytes and uses an initialized 8 KiB scratch buffer,
without loading whole files into memory. The example uses declarative CLI specs,
assumed allocator and stream capabilities, and a checked `!Void` entry point.
Each file has a scoped owner and an explicitly checked close; the final stdout
flush is checked too.

Unknown options and input or output errors stop the program with a failing exit
status. File errors include the path in their error trace. Output already written
before an error remains on stdout.
