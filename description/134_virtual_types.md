# Virtual types (vtable-based dynamic dispatch)

> “Abstracts are always monomorphized; request dynamic dispatch explicitly.”

## Use cases

* **Heterogeneous collections**
* **Plugins / FFI**: objects passed through a stable interface.
* **Smaller binaries**: one indirect call instead of N monomorphized versions.
* **Clear boundaries**: the user **chooses** when to pay for the indirect call.
- **Cost**: 1 pointer load + 1 **indirect call**.

Rule of thumb:

* “A **hot loop** limited by memory or compute” → static (generics).
* “**Boundaries** (IO/FFI/plugins) and heterogeneous data” → `Virtual`.

## Virtual-safety

A method of an `Abstract` is **virtual-safe** if, after type erasure:

- **Parameters and return values** are **erase-safe**:
  - primitives/POD, pointers, slices…
  - **Virtual#(X)** (if another abstract is needed).
- **No** pure abstract types or free generics appear **in the signature**.
- **No generics in the vtable**: signatures must be **monomorphic** after erasure.

> Multiple dispatch (MD) is **not** virtual-safe.

## Definition

```argi
Virtual#(.abstract: Abstract) : Type = (
  .allocator: &Allocator
  .data_ptr : &Any        -- fat pointer to the data
  .vtable   : &VTable#(abstract)
  .meta     : Meta        -- type_id, drop_fn, flags, storage, etc.
)
```

## Creation

```argi
assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
s : Rectangle = (1, 2)
vs := s | to_virtual(_, Shape, allocator)
```

## Uso

```argi
do_something (v: Virtual#(Shape)) -> () := {
  v.vtable.draw(v.data_ptr)        -- call virtual-safe method
}
```

Or, more ergonomic and compatible:

```argi
do_something (v: Shape) -> () := {
  draw(v)
}
```

> [!QUESTION] Should `Virtual#(Abstract)` implement `Abstract`?
> This is convenient. Consider whether it introduces complications.


## Interoperabilidad y ABI

Consider how to customize `Virtual` to fit different scenarios:

- Specify the order of functions.
- ...


> [!IDEA]
> Perhaps this can be done by overloading `to_virtual`.
> Could `Virtual` be a kind of implementable Abstract?


---

## Multiple dispatch compatibility

> [!IDEA] Explore vtables with multiple dispatch.
> This could be modeled as a dispatch decision graph applied by currying
> functions. Explore this idea.
