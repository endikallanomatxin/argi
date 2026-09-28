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
