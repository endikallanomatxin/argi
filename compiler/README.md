# ARGI COMPILER

To make it run:

```bash
zig build run -- build test.rg
```

The build script uses `llvm-config` to locate LLVM headers and libraries. Make
sure the LLVM development tools are installed and `llvm-config` is available in
your `PATH`.


## References

Zig's compiler: https://github.com/ziglang/zig/tree/master/lib/std/zig
Go's compiler:  https://github.com/golang/go/tree/master/src/go

