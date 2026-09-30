# Virtual types

Abstracts express static contracts and are monomorphized by default.
`Virtual#(.abstract: A)` explicitly requests runtime dispatch through the
contract `A`. It is useful for heterogeneous values and capability boundaries
such as allocators, streams, and error tracers.

## Borrowed handle

A virtual value is a borrowed handle to a concrete object implementing its
abstract, together with the method table needed to call that implementation.
Conversion does not allocate, copy the concrete object, or transfer ownership
of it. It adds neither an allocator nor a destructor to the handle.

The concrete owner remains responsible for initialization and cleanup. The
handle, references to the handle, and references returned through its methods
must obey the lifetimes of the concrete storage and any dependencies carried
by it. Keeping a virtual handle alive cannot keep an ended allocation or
storage generation alive.

The runtime representation consists of a data pointer and a vtable pointer.
These are compiler-managed, not source fields named `.data_ptr` or `.vtable`.
Programs invoke abstract methods through ordinary function calls.

> [!QUESTION]
> A stable foreign ABI, vtable slot ordering, and interoperability with externally
> constructed method tables are not specified. The two-pointer representation
> alone does not establish these guarantees.

## Creation

```rg
Shape : Abstract = (
    get_value(.self: &Self) -> (.value: Int32)
    set_value(.self: $&Self, .value: Int32) -> ()
)
Box : Type = (.value: Int32)
Box implements Shape

get_value(.self: &Box) -> (.value: Int32) := {
    value = self&.value
}
set_value(.self: $&Box, .value: Int32) -> () := {
    self&.value = value
}

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 42)
    shape :: Virtual#(.abstract: Shape) = to_virtual(.value = $&box)
    set_value(.self = $&shape, .value = 43)
    value ::= get_value(.self = &shape)
    if value != 43 { status_code = 1 }
}
```

`to_virtual` accepts a reference to a concrete object with an explicit
`implements` relationship and matching method implementations. Its abstract
argument can be inferred from an expected virtual result type. Without that
context, select the abstract explicitly:

```rg
shape ::= to_virtual#(.abstract: Shape)(.value = $&box)
compact ::= to_virtual#(Shape)($&box)
```

A named `.value` argument or a single positional reference is accepted.
Positional comptime type arguments omit the argument name. The concrete
object's implemented abstracts and the destination binding's name do not
select a target abstract: one concrete type can implement several contracts.

A pipe can borrow the result with `&_` or `$&_`:

```rg
assume tracer ::= NoopErrorTracer() | to_virtual#(ErrorTracer)($&_) | $&_
```

The concrete temporary and virtual wrapper remain alive for the enclosing
`assume` scope. Their references cannot escape that scope.

## Dispatch

Methods receive a reference to the virtual handle at the call site. Runtime
selection substitutes the concrete receiver pointer and calls the method in
that handle's table. The receiver need not be the first input; its position
comes from the abstract contract.

```rg
read_shape(.shape: &Virtual#(.abstract: Shape)) -> (.value: Int32) := {
    value = get_value(.self = shape)
}
```

A parameter declared as `Shape` requests the ordinary static abstract
mechanism. Use `Virtual#(.abstract: Shape)` explicitly when dynamic dispatch
is required. This dispatch support does not imply a general nominal
`Virtual<A> implements A` relationship.

A vtable slot has a fixed callable signature after erasure. The receiver's
concrete layout is hidden; other inputs and outputs must be usable without
knowing that layout. Ordinary scalar values, references to known types, and
explicit virtual handles can cross this boundary. A method-local generic
requiring a new instantiation at runtime cannot occupy one fixed slot.

Fallible methods carry a uniform error-tracer capability input, including
implementations that always succeed. Errors created by a selected method
therefore follow the same capability rules as static calls.

> [!QUESTION]
> Define the complete admissibility rules for `Self` outside the receiver,
> associated parameters, and multiple independently erased receivers. Runtime
> multiple dispatch is not established by the single-receiver method table.
>
> [!IMPLEMENTATION]
> The compiler supports the borrowed receiver dispatch described here, but
> does not yet provide a complete dedicated diagnostic for every inadmissible
> erased signature.

## Safety across implementations

Dynamic dispatch retains safety obligations. A method may return a reference
borrowed from its receiver, mutate caller-visible storage, or have effects on
owned or opaque storage. Those effects must remain valid through erasure.

When the concrete implementation is known, checking can use its specific
summary. At a boundary where it is unknown, checking conservatively combines
possible implementations: required liveness must cover every alternative,
while guarantees must hold across alternatives. Incompatible ownership or
storage transitions are rejected rather than hidden by the vtable.

Private concrete receiver fields are not fields of the virtual handle. A
returned borrow still depends on the receiver's storage; erasing its layout
must not erase that lifetime dependency. See `34_safety_model.md` for roots,
storage generations, and opaque storage.

> [!IMPLEMENTATION]
> Unknown dispatch currently uses a program-wide set of implementations found
> through virtual conversions. This can be more conservative than the actual
> runtime alternatives at a particular call site.
