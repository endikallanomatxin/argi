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
> `#run` and general compile-time conditions are not supported yet.
> `#if` currently accepts the target predicates described below, combined
> with `not`, `and`, `or`, and parentheses.

## Compilation target

`target_os("windows")`, `target_arch("aarch64")`, and `target_abi("gnu")`
are Boolean compile-time predicates. They describe the program's compilation
target, including during cross compilation, rather than the compiler host.
Names identify concrete OS, architecture, or ABI tags; unknown names are errors.
These compiler operations require one positional literal string argument and
have no runtime effects or capability inputs.

Use `#if` to select declarations, imports, or statements:

```rg
#if target_os("windows") {
    platform := import("./windows")
} #else {
    platform := import("./posix")
}
```

Only the selected branch contributes declarations or dependencies. Imports,
types, and foreign symbols in the discarded branch do not need to exist.
Nested selections are allowed. Conditions are checked even in discarded
branches, and branch delimiters must remain balanced. `#if` is a declaration
or statement selection, not a value-producing expression. An ordinary `if`
does not provide these dependency-selection guarantees.

Target information is not a runtime OS capability and need not become a type
parameter on every resource. Libraries concentrate platform selection in
private adapters behind ordinary public resource contracts.

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
