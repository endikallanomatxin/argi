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
s :: Rectangle = (1, 2)
vs :: Virtual#(.abstract: Shape) = to_virtual($&s)
```

The `.abstract` comptime argument can be inferred from an expected
`Virtual#(.abstract: Shape)` result type. Both a named `.value` argument and
a single positional reference are accepted:

```rg
vs :: Virtual#(.abstract: Shape) = to_virtual(.value = $&s)
explicit ::= to_virtual#(Shape)($&s)
```

Without a contextual result type, `.abstract` must be supplied explicitly.
The concrete object's implemented abstracts and the destination binding's
name do not select a target abstract.

Positional comptime type arguments omit the field name. A pipe can borrow
the virtual result with `&_` or `$&_`:

```rg
assume shape ::= Rectangle(1, 2) | to_virtual#(Shape)($&_) | $&_
```

The constructed object and its virtual wrapper are borrowed temporaries,
kept alive for the enclosing `assume` scope. This conversion does not move
ownership into the capability; references cannot escape those temporaries.

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
