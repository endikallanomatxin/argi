# Directory tree

Build from the repository root, then run the compiled tool:

```sh
zig build
./zig-out/bin/argi build tests/usecase_tests/04_tree
./tests/usecase_tests/04_tree/build/output --root path/to/directory --depth 2
./tests/usecase_tests/04_tree/build/output --help
```

The declarative schema defines short aliases, required values, a default depth
and help text. The same schema generates help. Invoke help on its own; ordinary
invocations require a root. Depth zero visits nothing, even if the root does
not exist. The root's children have depth one. Directories at the selected
limit are listed but not descended into. Enumeration order is unspecified.
Each emitted entry owns its path until its loop branch ends.

The walker avoids deliberate link traversal and bounds the number of open
levels. Native path lookup races remain possible, so this tool is not a
filesystem security boundary. Errors terminate traversal and release pending
owners; already printed entries cannot be rolled back.
