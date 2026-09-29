# Initialization and deinitialization

Storage and a live value are different things. A place can exist before it
contains a value, and raw allocated bytes do not yet contain a `T`. A value
becomes live only after it has been fully initialized. Reading it beforehand
is an error.

`init` constructs a value in a destination place. A type may define an `init`
operation to establish its invariants; types that need no custom constructor
can be initialized directly. The destination may be uninitialized when `init`
begins, but it must contain a complete value on every successful exit. A
failed initialization must leave no live partial value or leaked resource.
An infallible `init` returns `()`. A fallible one returns one
`Errable#(.t: Void, .reasons: R)` result: `..ok` means the destination now
contains a complete value, and `..error` means it remains empty. The caller
must inspect that result before using the destination. The compiler checks
these conditions for each outcome.

Calling `T(...)` uses the same initializer with a temporary destination. It
produces `T` for an infallible initializer or
`Errable#(.t: T, .reasons: R)` for a fallible one. The successful value is
transferred from the destination into `..ok`; an error carries no `T`.

> [!IMPLEMENTATION]
> A direct call to a fallible `init` currently needs a local destination
> place that the safety checker can identify. Destinations reached only
> through another function's pointer parameter are not yet supported.

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
