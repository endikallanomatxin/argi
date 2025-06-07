# ARGI COMPILER

## Prerequisites

The build script needs to know where LLVM is installed. Normally it attempts to
invoke `llvm-config` but this may fail in restricted environments. As an
alternative you can provide the paths manually via the following environment
variables before running `zig build`:

```
export LLVM_INCLUDE_DIR=/path/to/llvm/include
export LLVM_LIB_DIR=/path/to/llvm/lib
export LLVM_LIBS="$(llvm-config --libs)"
```

If these variables are set `llvm-config` will not be executed.

## Building

You can build the compiler by doing:

```bash
zig build
```

That will create a binary called `argi` in the `zig-out/bin/` directory.

Then you can build a `.rg` file by running:

```bash
./zig-out/bin/argi build file.rg
```

You can also run the compiler directly with:

```bash
zig build run -- build file.rg
```

## Running Tests

You can run the tests in `test/` by doing:

```bash
zig build test
```

If testing doesn't work, the same can be checked by compiling the files
independently:

```bash
zig build
./zig-out/bin/argi specific_test_file.rg
```

