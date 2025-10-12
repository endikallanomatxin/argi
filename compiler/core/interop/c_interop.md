## C interoperability

Es muy importante que usar librería en c sea fácil.
Casi todo el código útil del mundo está escrito en c.

Zig offers the `zig translate-c` command, which converts C headers into Zig's syntax. This is particularly useful for complex C libraries, as it automates the creation of Zig bindings.

**Usage:**
`zig translate-c mylib.h > mylib.zig`

You can then import the generated `mylib.zig` into your Zig code:

```
const mylib = @import("mylib.zig"); 
pub fn main() void {
	mylib.some_c_function();
}
```

## Null terminated arrays and strings

