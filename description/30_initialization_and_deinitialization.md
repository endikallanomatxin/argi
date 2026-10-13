# Initialization and deinitialization

Storage and a live value are different things. A place can exist before it
contains a value, and raw allocated bytes do not yet contain a `T`. A value
becomes live only after it has been fully initialized. Reading it beforehand
is an error.

Canonical construction uses the standard `Init` contract. Its selected
conformance defines an argument record and a result of `T` or `Errable#(T, R)`.
Calling `T(...)` completes that record and invokes the selected `init` operation.
No uninitialized destination is passed into it: the successful value is returned
directly or transferred into `..ok`. Ordinary ownership and automatic cleanup
apply to intermediate values on every exit.

```rg
Point: Type = (.x: Int32, .y: Int32)
implement Init#(Point) (
    .Args: Type = (.x: Int32, .y: Int32 = 0)
    .Result: Type = Point
    .init = (.args: Args) -> (.result: Result) {
        result = (.x = args.x, .y = args.y)
    }
)

point ::= Point(.x = 10)
```

Generic implementations declare their compile-time parameters after `implement`:

```rg
Box#(.T: Type): Type = (.value: T)
implement#(.T: Type) Init#(Box#(T)) (
    .Args: Type = (.value: T)
    .Result: Type = Box#(T)
    .init = (.args: Args) -> (.result: Result) { result = (.value = args.value) }
)
```

The requested type, such as `Box#(Int32)`, selects the conformance. Argument or
result mismatches do not select another conformance or bypass custom construction.
Record defaults retain scalar literals, payload-free choice variants and lexical
reach directives without executing runtime expressions during type materialization.
The selected operation preserves argument loans and projected output dependencies.

Types without custom construction can use structural initialization. Legacy
`T init(...)` declarations remain available while their families migrate; mixing
legacy initializers with `Init` for one family is rejected. Alternative factories
use ordinary functions with distinct names.

Custom destruction uses the standard `Deinit` contract. Its consuming operation
receives a mutable reference and returns no values:

```rg
implement Deinit#(Point) (
    .deinit = (.self: $&Point) -> () {}
)

implement#(.t: Type) Deinit#(Box#(.t: t)) (
    .deinit = (.self: $&Box#(.t: t)) -> () {}
)
```

Explicit calls use `Deinit#(Point).deinit(.self = $&point)` or the unqualified
`deinit(.self = $&point)` when its operation identity is unambiguous. Automatic
cleanup selects the same conformance and operation, including generic
specializations. The implementation must prove definite consumption of its
receiver. Consuming an owner may empty its owned storage; it grants no permission
to consume borrowed referents or retain new values in hidden storage.

Bundled owners retain their deallocation evidence, so their destructors do not
require a separate allocator argument. Legacy `T deinit(...)` declarations remain
supported for unmigrated families. Mixing both mechanisms for one family is an
error; legacy declarations are a migration adapter rather than another lifecycle
model.

`deinit` ends a live value and releases the resources it is responsible for.
A type may define this operation when cleanup is needed. Types without one do
not need a dummy `deinit`. After deinitialization, the place still exists, but
its former value cannot be read or destroyed again. The place may later hold
a new value.

## Automatic cleanup

A local value that requires cleanup is cleaned at lexical scope exit,
including normal and error exits. If its type has a `deinit` operation,
cleanup calls it; otherwise aggregates are cleaned field by field.

Cleanup follows initializedness: an already deinitialized place is not
destroyed twice. Replacing a live value first cleans the old one, then
initializes the same storage with the replacement.

`#defer` schedules a statement to run when the current scope exits, including
on a return or error propagation. Deferred statements run in reverse order,
before automatic cleanup of the scope's locals. Use it for an exit action
that automatic cleanup does not provide; a local value with a suitable
`deinit` does not need a deferred `deinit` call.

Deferred actions cannot return from the containing function or propagate errors
with `!`, `!!`, or `!!!`: doing so would bypass remaining deferred actions and
owner cleanup. Handle failures locally with `handle`. A handler may update an
output binding, such as setting `status_code = 1`, and report the error while
allowing cleanup to continue. Calls to ordinary functions remain valid; their
returns belong to those functions rather than to the deferred action.
Likewise, `break` and `continue` may target loops inside the deferred action,
but cannot exit an enclosing loop outside it.
