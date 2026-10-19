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
> `#run` currently accepts resolved function calls with constant scalar or
> aggregate arguments and representable results. Closed calls and selected
> integer arithmetic/comparisons and aggregate field/index projections can compute
> those arguments. Calls use the checked bytecode
> subset and its execution limits; references, resource-owning results and host
> effects cannot cross this boundary. Requests in specialized bodies are retained,
> and nested requests are resolved before their callers. Integer results can
> determine type and function specialization arguments: semantic resolution
> waits for the selected dependency bodies, proves their safety, and resumes
> with the frozen result. Suspended specializations preserve temporary pointer,
> array, record, choice and generic type descriptions across selection rollback.
> Defaults, inferred choice identities and declaration origins must already be
> stable; otherwise the request remains pending.
> Within function bodies, computed `#if` conditions accept closed Boolean calls,
> integer comparisons, and scalar or aggregate projections in that same subset.
> Generic conditions are evaluated separately for each specialization. Both arms
> must parse, but only the selected arm is materialized and safety-checked.
> Selected statements belong to the containing scope, like target selection;
> use an explicit nested block when a separate lifetime is needed.
> Runtime inputs cannot determine a compile-time condition.
> CLI compilation also evaluates closed module-level conditions before adding
> the selected declarations and discovering their imports. Nested selections
> retain original source offsets; inactive imports need not exist. Program entry
> discovery follows selection, so `main` can be declared in a selected arm.
> `argi test` uses the same selection to discover active tests, without selecting
> `main` or executing test bodies during discovery.
> REPL module preparation and later imports use the same staged selection driver.
> Selected namespaces remain stable across subsequent commands; reset restores
> the initial modules, and later imports can read updated sources.

The experimental `argi run --vm <directory>` command uses the shared bytecode
executor for runtime execution. Explicit `#run` requests use that executor during
compilation regardless of the selected runtime backend. The supported subset and
limits are documented in [usage](../docs/usage.md#experimental-bytecode-execution).

## Compilation target

`target_os("windows")`, `target_arch("aarch64")`, and `target_abi("gnu")`
are Boolean compile-time predicates. They describe the program's compilation
target, including during cross compilation, rather than the compiler host.
Names identify concrete OS, architecture, or ABI tags; unknown names are errors.
These compiler operations require one positional literal string argument and
have no runtime effects or capability inputs.

`target_pointer_bits(64)` checks the target pointer width with a positional
integer literal. It includes ABI-specific widths, such as 32-bit pointers on
x86_64 with the x32 ABI. The numeric conversion conformances use this predicate
to classify `UIntNative` widening conversions.

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
Nested selections are allowed. Target predicates are validated even in discarded
branches, and branch delimiters must remain balanced. Computed conditions inside
an unselected function-body branch are not evaluated. `#if` is a declaration
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
