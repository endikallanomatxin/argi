# Compile-time computation

Argi provides metaprogramming by executing Argi code at compile time, in the
spirit of Zig's `comptime`. Compile-time values can shape types, specialize
functions, and select code before the program runs.

## Established model

`#(...)` declares compile-time parameters. A call supplies concrete values
with `name#(.parameter = value)`, and the compiler specializes the generic
declaration for those values. Type parameters are one case; parameters may
also hold other compile-time values, such as array lengths.

```rg
Array#(.n = 4, .t = Int32)
```

`type_of(.value = expression)` obtains the type of an expression as a
compile-time value. Type queries do not execute the expression for its
runtime effects.

Explicit compile-time execution uses `#run`. Conditional compilation uses
`#if`: its condition is evaluated at compile time, and only the selected
branch is compiled. This differs from running an ordinary `if` inside
`#run`; the latter executes the conditional during compile-time evaluation.

> [!IMPLEMENTATION]
> `#run` and `#if` are part of the intended language design but are not yet
> supported by the compiler.

## Open questions

> [!QUESTION]
> Should compiler-recognized operations such as `import(...)`, `type_of(...)`,
> and `size_of(...)` share a `#` prefix? Define whether `#` marks compile-time
> evaluation, special compiler syntax, or something else.

> [!QUESTION]
> Which operations may `#run` perform, and how are access to files, system
> resources, diagnostics, and reproducible builds controlled?

> [!QUESTION]
> Should code be able to ask whether it is executing at compile time, for
> example through `#is_compile_time`? If so, define how that affects the
> behavior of a function used in both phases.

> [!QUESTION]
> How should compile-time code report errors and warnings through libraries
> and editor tooling? Functions run at compile time may need to return errors
> that become compiler diagnostics or LSP warnings.

> [!QUESTION]
> When generic code uses an abstract type, should `type_of` expose the
> concrete type after specialization? Define what can be observed before and
> after that specialization.

## Exploratory ideas

> [!IDEA]
> `#atcalls` could run validation at compile time for every call to a
> function. This needs rules for available argument values, diagnostics,
> and interaction with generic specialization.

> [!IDEA]
> A save-time or editor-time macro could rewrite source to add boilerplate,
> such as declarations that bring system resources into scope. Any such
> mechanism should make its edits visible and reviewable.

> [!IDEA]
> `#maintain` could retain a value computed at compile time for later use.
> Its exact meaning and need remain to be established.

> [!IDEA]
> `#code` could represent code as a structured compile-time value. A
> corresponding `#insert` could splice such values, but inserting raw strings
> would make expansion and diagnostics difficult to trace. Neither mechanism
> has defined semantics yet.
