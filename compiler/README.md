# ARGI COMPILER

To make it run:

```bash
zig build run -- build test.rg
```

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


## References

Zig's compiler: https://github.com/ziglang/zig/tree/master/lib/std/zig
Go's compiler:  https://github.com/golang/go/tree/master/src/go

