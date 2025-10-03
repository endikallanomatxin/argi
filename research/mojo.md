## A deep dive on ownership with Chris Latner

[Youtube video](https://youtu.be/9ag0fPMmYPQ?si=OAAF81EL9ZQlRiDq)


### Learning from rust

Rust seems theoretically simple, but gets really complicated.

> Mojo has learned things from Rust, but doesn't want to be Rust!!


### Mojo type support

Supports types that:

- Are not copiable / movable. (f.e. Atomics) But all are destructable.
- Have custom copy/move/destroy logic
- Live in memory with identity
- Live in non-default address spaces (f.e. GPU memory)


Good support for common specializations: @register_passable, @value, ...

Generality might seem esoteric, but crucial when you need it
(xref "Pin" and related pain in async rust)

### Type checker

- No bidirectional or Hindley-milner or other fancy type checking
- Type of y and z determine type of y*z
- Similar to how C++ type checks expressions

Recursively emits exprs to MLIR and return:
- Result IR node + value kind
- Three value kinds, RValue, LValue, BValue
- Mojo is unusual: no "type checked AST"


### RValue: an owned value

> In mojo, it automatically copies all but last and moves last.

An RValue is an owned value with unique ownership.
- Function results are typically "owned"
- Result of transfer operator is owned: somevalue^

Can be passed to 'owned' arguments without copy
- Similar-ish to "void use(String arg)" in C++

### LValue: that which can be assigned / mutated

An Value is something that may be mutated
• Assigned to
• Passed inout
• Mutable reference taken
• No-alias due to exclusivity (TODO)

Examples: inout / owned arguments and var decls
• Also "x. field" dotted off them

Similar-ish to "void use (String &arg)" in C++

> In mojo inout keyword makes the argument borrow the ownership and then give
> it back.

### BValue: a borrowed value

A reference to value owned by someone else
• Can read from it
• Can form an immutable reference
• Very important to avoid copies
• Can alias other BValues, but not LValues (TODO)

Example: borrowed args, exprs derived therefrom
• Mojo defaults to borrowed arguments

Similar-ish to "void use (const String garg)" in C++

---

> [!TODO] Study full video in more depth

