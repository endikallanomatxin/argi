# Initialization and deinitialization

Storage and a live value are different things. A place can exist before it
contains a value, and raw allocated bytes do not yet contain a `T`. A value
becomes live only after it has been fully initialized. Reading it beforehand
is an error.

Canonical construction uses `Init<T, Args>`. The target and argument record
are participants; their selected conformance determines `T` or `Errable<T, R>`
as its associated Result.
Calling `T(...)` completes that record and invokes the selected `init` operation.
No uninitialized destination is passed into it: the successful value is returned
directly or transferred into `..ok`. Ordinary ownership and automatic cleanup
apply to intermediate values on every exit.

```rg
Point := (.x: Int32, .y: Int32)
implement Init<Point, (.x: Int32, .y: Int32 = 0)> (
    .Result: Type = Point
    .init = (.args: (.x: Int32, .y: Int32)) -> (.result: Result) {
        result = (.x = args.x, .y = args.y)
    }
)

point ::= Point(.x = 10)
```

Generic implementations declare their compile-time parameters after `implement`:

```rg
Box := <.T: Type> (.value: T)
implement<.T: Type> Init<Box<T>, (.value: T)> (
    .Result: Type = Box<T>
    .init = (.args: (.value: T)) -> (.result: Result) { result = (.value = args.value) }
)
```

The requested type, such as `Box<Int32>`, and input argument types select the
conformance together. Generic argument fields can retain a concrete allocator
without adding it to the target type. Constructor syntax contextualizes literals
and completes defaults against applicable argument patterns, then uses contract
specificity. Incomparable applicable patterns are ambiguous. The result never
selects a conformance, and an incompatible selected result cannot bypass custom
construction.
Record defaults retain scalar literals, payload-free choice variants and lexical
reach directives without executing runtime expressions during type materialization.
The selected operation preserves argument loans and projected output dependencies.
References carried inside Args retain effects on their referents, including
consumption and invalidation. Copying Args does not let its local field-slot
updates overwrite caller slots. Repeated consumption and aliasing between
consumed reference fields are checked across that boundary.

When Args determines every parameter of a nominal family, its application can
be omitted: `Box(.value = byte)` infers the same target as `Box<UInt8>` for a
UInt8 input. This inference also applies inside generic bodies. If several
conformances infer different targets and none dominates, specify the target
explicitly; Result is never used to choose its missing parameters.

All bundled core and official more constructors use this contract. `Range`
uses one Args record with default start and step. Scaled durations, relative
deadlines, precise Unix timestamps, and paths copied from views use ordinary
named factories. Single-use capabilities reuse named `once` functions as their
`init` members, preserving entrypoint call-graph checks.

Types without custom construction can use structural initialization. The old
`T init(...)` declaration syntax is rejected with a migration diagnostic. Init
evidence owns construction; there is no separate nominal constructor registry
or inference from constructor return types. Alternative factories use ordinary
functions with distinct names.

Custom destruction uses the standard `Deinit` contract. Its consuming operation
receives a mutable reference and returns no values:

```rg
implement Deinit<Point> (
    .deinit = (.self: $&Point) -> () {}
)

implement<.t: Type> Deinit<Box<.t: t>> (
    .deinit = (.self: $&Box<.t: t>) -> () {}
)
```

Explicit calls use `Deinit<Point>.deinit(.self = $&point)` or the unqualified
`deinit(.self = $&point)` when its operation identity is unambiguous. Automatic
cleanup selects the same conformance and operation, including generic
specializations. The implementation must prove definite consumption of its
receiver. Consuming an owner may empty its owned storage; it grants no permission
to consume borrowed referents or retain new values in hidden storage. Replacing
references in borrowed storage is not authorized by consuming the owner. Such
effects require a protocol that declares them, or an ordinary deferred action
whose concrete effects are checked at its call site.

Bundled owners retain their deallocation evidence, so their destructors do not
require a separate allocator argument. Cleanup declarations use only
`implement Deinit<T>`; the retired `T deinit(...)` syntax receives a migration
diagnostic. Ordinary functions named `deinit` have ordinary call effects and
create no automatic cleanup obligations.

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

A record may be initialized field by field. Once all fields are initialized,
the complete value has the same cleanup as a whole-value initializer. If the
scope exits before completion, only its initialized owning fields are cleaned;
the incomplete record's `deinit` is not called. This applies recursively to
partially initialized nested records and to early exits.

`defer` schedules a statement to run when the current scope exits, including
on a return or error propagation. Deferred statements run in reverse order,
before automatic cleanup of the scope's locals. Use it for an exit action
that automatic cleanup does not provide; a local value with a suitable
`deinit` does not need a deferred `deinit` call.

`defer` is a reserved keyword, as is `implement`. It has no directive prefix:
write `defer { ... }` or `defer cleanup(...)`. The former `#defer` spelling is
rejected with a migration diagnostic.

Deferred actions cannot return from the containing function or propagate errors
with `!`, `!!`, or `!!!`: doing so would bypass remaining deferred actions and
owner cleanup. Handle failures locally with `handle`. A handler may update an
output binding, such as setting `status_code = 1`, and report the error while
allowing cleanup to continue. Calls to ordinary functions remain valid; their
returns belong to those functions rather than to the deferred action.
Likewise, `break` and `continue` may target loops inside the deferred action,
but cannot exit an enclosing loop outside it.
