# Once Functions

`once` marks a named function as globally single-use from the perspective of
the compiled entrypoint.

This is a compile-time restriction. It is not a runtime guard, hidden flag, or
idempotence mechanism.


## Core idea

If a function is defined with `once`, the reachable call graph rooted at the
compiled entrypoint may consume that function at most one time.

Example:

```argi
once init_terminal() -> () := {
    ...
}

main() -> (.status_code: Int32) := {
    init_terminal()
    status_code = 0
}
```

This is valid.

```argi
once init_terminal() -> () := {
    ...
}

main() -> (.status_code: Int32) := {
    init_terminal()
    init_terminal()
    status_code = 0
}
```

This is invalid, because the same `once` function is consumed twice from the
same entrypoint.


## Reachability matters

The restriction is not checked textually across the whole repository.

It is checked only on the subgraph that is reachable from the entrypoint being
compiled.

That means a library may define multiple helpers that consume the same `once`
function, as long as a concrete entrypoint does not reach more than one of
those consumptions.

Valid library shape:

```argi
once init_terminal() -> () := {
    ...
}

path_a() -> () := {
    init_terminal()
}

path_b() -> () := {
    init_terminal()
}
```

Valid entrypoint:

```argi
main() -> (.status_code: Int32) := {
    path_a()
    status_code = 0
}
```

Invalid entrypoint:

```argi
main() -> (.status_code: Int32) := {
    path_a()
    path_b()
    status_code = 0
}
```


## Static, not runtime

`once` does not mean “execute only the first time at runtime”.

This first design means:

- the compiler tracks which `once` functions may be consumed
- if the same `once` function appears more than once in the reachable call
  graph of the entrypoint, compilation fails

As a consequence, mutually exclusive branches still count as duplicate
consumption in this first model:

```argi
once init_terminal() -> () := {
    ...
}

main(.cond: Bool) -> (.status_code: Int32) := {
    if cond {
        init_terminal()
    } else {
        init_terminal()
    }
    status_code = 0
}
```

This is intended to be invalid in the first iteration.


## Intended use

`once` is meant for operations that should have exactly one consumer in the
compiled program shape, such as:

- initialization that must happen from a single path
- bootstrap/setup steps that should not be duplicated accidentally
- unique construction of process-wide capabilities

It is not primarily an ergonomics shortcut for idempotent initialization.
If the desired meaning is “safe to call many times, but only the first one
does work”, that is a different runtime feature.


## First iteration scope

The first implementation should stay intentionally narrow:

- only named functions can be marked `once`
- `once` applies to function definitions, not arbitrary declarations
- the main check is performed from the compiled entrypoint
- diagnostics should explain both the repeated `once` function and the path
  that causes the duplicate consumption

Possible restrictions that are reasonable in the first version:

- disallow overload sets involving `once`
- disallow generic `once` functions
- disallow taking `once` functions as ordinary first-class values

Those restrictions are not part of the long-term goal, but they may simplify
the first implementation.


## Mental model

A normal function may be called any number of times.

A `once` function behaves more like a unique semantic resource:

- it can be consumed by at most one reachable call path set
- duplication is a compile error
- the check is global relative to the chosen entrypoint, not local to a single
  function body

This keeps the feature aligned with Argi's general direction:

- explicit capabilities
- compile-time semantic restrictions
- avoiding hidden runtime state when the intent can be modeled statically
