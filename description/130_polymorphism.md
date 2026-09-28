# Polymorphism

## Use cases

- Homogeneous collections for each different type

- Heterogeneous collections

- Functions that can operate on different types defined at once

- Iterators

- IO sources and sinks
- Databases


## Implementations

1. Static structural (like Go/anytype, but checked):
	Monomorphization, zero call overhead, and possible inlining.
	Clear compile-time errors when a method or field is missing.
	Risk:
		Binary growth when there are many instances.
	Use for:
		Performance-critical generic algorithms.
		Cases where the concrete type is known at the instantiation site.
		APIs that should benefit from inlining or constant propagation.

2. Dynamic dispatch with a vtable (interface object):
	A “fat pointer” { data_ptr, vtable_ptr } with runtime dispatch.
	Costs:
		Indirect call, no inlining by default, and managing data_ptr ownership and lifetime.
	Use for:
		Heterogeneous lists of “things that satisfy X”.
		Plugins, FFI, and module boundaries with a stable ABI.
		Cases where reducing code size is worth an indirect call.

3. Dynamic dispatch with a tagged union (closed sum)

## Ergonomy constructs

### Multiple dispatch

Lets operations on different data types share a name.
(OOP does this per object, with one argument; multiple dispatch allows it for all arguments.)

### Generics (for parametric polymorphism)

Generics allow for a clean and compact way of doing monomorphization at compile
time.

With generics you can do all static polymorphism, but sometimes it is not the
most ergonomic way.

### Abstract types (for subtype polymorphism)

Unifies static and dynamic dispatch under one construct.
It is monomorphized by default, but can be converted to `Virtual` for runtime
dynamic dispatch.

### Virtual types (for dynamic polymorphism)

Virtual types are used for vtables.

```
Virtual#(Foo) : Type = (
    .data_ptr : &Any       -- or inline storage for SBO
    .vtable   : &Foo.Vtbl  -- function pointer table derived from the Abstract
    .meta     : Meta       -- type_id, ownership flags, storage, etc.
)
```

Requires an allocator.

For an abstract to be Virtual-safe:

- Its methods must have exactly one possible dispatch target.

- It cannot have Abstract input fields.

> [!QUESTION]
> This may be especially inconvenient for inputs such as allocators or integers
> used as indices. Abstracts are useful in these cases, but this would require
> making many things concrete instead of polymorphic.

Uso:

```
process_foo (f: Virtual#(Foo)) -> () := {
    f.vtable.do_something(f.data_ptr, ...)
}
```
