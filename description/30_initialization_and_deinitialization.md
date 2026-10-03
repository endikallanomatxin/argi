# Initialization and deinitialization

Storage and a live value are different things. A place can exist before it
contains a value, and raw allocated bytes do not yet contain a `T`. A value
becomes live only after it has been fully initialized. Reading it beforehand
is an error.

A constructor is declared as `T init(...)` and returns one complete `T`, or
one `Errable#(.t: T, .reasons: R)` when construction can fail. Calling `T(...)`
invokes that constructor. No uninitialized destination is passed into `init`;
the successful value is returned directly or transferred into `..ok`. An error
carries no constructed value. Ordinary ownership and automatic cleanup rules
apply to intermediate values on every exit.

```rg
Point init(.x: Int32, .y: Int32) -> (.result: Point) := {
    result = (.x = x, .y = y)
}
```

The type before `init` names the nominal type declaration in the same module.
It associates the constructor with that type, independently of its output.
The association narrows the candidate set; input types select an overload
within it. Output types do not distinguish overloads. A visible constructor
owns construction even when its inputs do not match a particular call;
callers cannot bypass it through automatic field-wise construction. Types
without custom constructors can be initialized directly.

Constructors declare their own compile-time parameters after `init`, exactly
as ordinary functions do. The associated name identifies a type family;
the returned type expresses its concrete generic arguments:

```rg
Box init#(.t: Type)(.value: t) -> (.result: Box#(.t: t)) := {
    result = (.value = value)
}
```

Parameters can be inferred from inputs or from an explicitly requested type
such as `Box#(.t: Int32)(...)`. The requested type can bind constructor
parameters but cannot select overloads distinguished only by return type.
Additional constructor parameters follow ordinary inference and default rules;
no parameters are implicitly introduced into the constructor's scope.

A destructor is declared as `T deinit(...)`. Like constructors, destructors
belong to a nominal type declared in the same module and declare their own
compile-time parameters. They receive a mutable reference to that type and
return no values. The receiver name remains an ordinary input name; additional
inputs follow ordinary call resolution, including assumed capabilities.

```rg
Point deinit(.self: $&Point) -> () := {}
```

Explicit calls use `deinit(.self = $&point)`. Automatic cleanup searches the
associated type family before matching the receiver and any additional inputs.
A generic destructor expresses its concrete receiver in the input type:

```rg
Box deinit#(.t: Type)(.self: $&Box#(.t: t)) -> () := {}
```

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
