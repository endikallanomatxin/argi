# Streaming cat CLI

Build with `zig build`, then `./zig-out/bin/argi build tests/usecase_tests/01_cat_cli`.
Run `tests/usecase_tests/01_cat_cli/build/output [FILE...]` (add `.exe` on Windows).

The program concatenates files in argument order. With no files it reads standard
input; `-` reads standard input at that position. Use `--` before filenames that
start with a hyphen. `-h` or `--help` prints help without opening any files.

The free function `transfer_stream` takes a writer and a reader. For buffered writers
it reads directly into their available buffer space, preserving pending output
and binary bytes. This example lends one initialized 8 KiB buffer to a
`BufferedWriter` over stdout, without loading whole files into memory or using a
separate transfer buffer. It uses declarative CLI specs,
assumed allocator and stream capabilities, and a checked `!Void` entry point.
Each file has a scoped owner and an explicitly checked close. A checked
`#defer flush(writer)!` beside the writer setup flushes stdout on every scope
exit, including help and error returns.

Unknown options and input or output errors stop the program with a failing exit
status. File errors include the path in their error trace. Output already written
before an error remains on stdout.
