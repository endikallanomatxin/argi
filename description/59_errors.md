# Errors

Accepted direction:
- Propagation and ergonomics along the lines of Zig.
- Accumulated human-readable context and traces during propagation, as in
  `anyhow`.
- An error is no longer identified by an arbitrary `Type`; it is identified by
  a nominal `choice option`.

## Choice options

A `choice option` is declared on its own:

```rg
..file_not_found
..permission_denied
..invalid_format
```

Semantics:
- Each declaration defines a nominal symbol.
- The compiler assigns each option a unique numeric ID during compilation.
- That ID is the option's actual identity.
- The text `..name` is only how the option is referenced.

Use does not declare an option:
- `..file_not_found` in value position refers to an existing option.
- If it does not exist, it is an error.

## Open choices

Options are grouped into closed `choices` when typing or exhaustiveness is
needed.

```rg
reason : (..file_not_found, ..permission_denied) = ..permission_denied
```

A `choice` can be:
- anonymous, as in the previous example
- named, using a language alias or type

The `choices` used for errors are closed and finite.

## Error values

The trace remains part of the error itself.

```rg
Error#(.reasons: Choice) : Type = (
    .reason: reasons
    .trace: ErrorTrace
)
```

Restricciones:
- `.reason` must be a `choice` without payloads.
- `.trace` uses the current trace-entry mechanism.

## Error unions

`Errable` is defined over a set of reasons:

```rg
Errable#(.t: Type, .reasons: Choice) : Type = (
    ..ok t
    ..error Error#(.reasons = reasons)
)
```

Consequences:
- A function declares the set of reasons it can return.
- `!` can propagate a subset into a compatible superset.
- The compiler/codegen remaps tags between different sets.

Example:

```rg
..file_not_found
..permission_denied

read_file() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found))) := {
    result = ..error(.reason = ..file_not_found)
}

load_file() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found, ..permission_denied))) := {
    value := read_file()!
    result = ..ok value
}
```

For the common single-result case there is also shorthand syntax:

```rg
load_file() -> !Int32 := {
    value := read_file()!
    result = ..ok value
}
```

`-> !T` means a single output binding named `result` whose type is an `Errable`
returning `T`. In this special form, the compiler infers the reasons from the
body and closes the return `Errable` after semantic analysis.

The same inference path is also available when the output is written
explicitly as `Errable#(.t: T)` and omits `.reasons`:

```rg
load_file() -> (.result: Errable#(.t: Int32)) := {
    value := read_file()!
    result = ..ok value
}
```

This is currently accepted only in function outputs. Outside function output
positions, `Errable#(.t: T)` still requires an explicit `.reasons`.

The compiler can also infer a narrower subset of the declared reasons by
looking at the actual propagation and return sites in the function body. That
inferred subset is surfaced in tooling hover even when the full declared
`.reasons` are still written explicitly in source.

In `core`, the same idea is already used for file opening, filesystem, and
stream failures:

```rg
..file_open_failed
..path_open_failed
..stream_read_failed
..stream_write_failed
..stream_flush_failed
..stream_close_failed
..out_of_memory

open_read(.p: $&File, .path: &Char)
    -> (.result: Errable#(.t: Bool, .reasons: (..file_open_failed)))

read_file(.self: &FileSystem, .path: StringView)
    -> (.result: Errable#(
        .t: String,
        .reasons: (..path_open_failed, ..stream_read_failed, ..stream_close_failed, ..out_of_memory),
    ))

read_byte(.self: $&Reader)
    -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed)))

write_byte(.self: $&Writer, .byte: UInt8)
    -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
```

`read_line()` and `read_file()` explicitly propagate `..out_of_memory`.
They delegate buffer creation and growth to fallible `String` helpers.

In `core`, the idiomatic approach for growth or allocation operations is no
longer:
- a raw pointer checked against `0`
- a `Bool` indicating whether allocation succeeded

Instead, use:
- `allocate(...) -> Errable#(.t: Allocation, .reasons: (..out_of_memory))`
- helpers such as `string_with_capacity(...)`
- growth operations returning `Errable#(.t: Void, .reasons: (..out_of_memory))`

This is already used in `String` and the fallible paths of `DynamicArray`
(`push_growing`, `insert_growing`, `dynamic_array_grow_growing`).

EOF remains outside the error channel:

```rg
ReadByte : Choice = (
    ..ok UInt8
    ..end
)
```

## Propagation

`!` and `!!`:
- short-circuit
- execute `defer`s
- add an entry to the trace
- require the current `Errable` to represent every propagated reason
- can be used in expression position or as a standalone statement, for example
  `step()!`, when the `..ok` value is not needed

They are already used in common expression contexts:
- bindings: `value := read_file()!`
- call arguments: `use(.x = read_int()!)`
- condiciones: `if ready()! { ... }`
- asignaciones: `cached = load()!`
- sentencias puras: `flush()!`

`!!` also attaches textual context to the trace entry.

Current direction for reason inference:
- The signature still spells out the complete declared set.
- `-> !T` already allows `.reasons` to be omitted in the special case of a
  single `result` output.
- `Errable#(.t: T)` without `.reasons` is also accepted in explicit function
  outputs.
- Semantizing infers a subset from `return`, output assignments, and `!` / `!!`
  propagation.
- Hover shows this inferred subset without adding noise to the code.
- The next step is to allow `.reasons` to be omitted in more places once this
  inference is robust enough across modules.

## Exhaustividad

Exhaustiveness is checked against a closed `choice`, not a standalone option.

This enables:
- `match` on `Errable`
- checks on `.reason`
- safe remapping between subsets and supersets of reasons

## Handling errors

`handle` provides a shorter form for handling an `Errable`:

> [!IMPLEMENTATION]
> The `handle` form is not implemented yet.

```argi
my_thing := fallible() handle value, error {
    match error.reason {
        ..file_not_found {
            value = 0
        }
        ..permission_denied {
            report_trace(.trace = &error.trace)
            value = 1
        }
    }
}
```

Expected semantics:
- `handle` would be syntactic sugar specific to `Errable`.
- The expression on the left must have type `Errable#(.t: T, ...)`.
- `value` would be the shared result slot.
- If the `Errable` is `..ok x`, then `value = x`.
- If it is `..error(...)`, the block runs with `error` bound to the complete
  error payload.
- Use regular `match` on `error.reason` inside the block.
- The block does not return a value specially; it only assigns to `value`.
- The complete construct produces `value`.
- The compiler should require `value` to be assigned on every path through the
  error block.

Motivation:
- It does not introduce a new `match` form.
- It does not introduce value-returning blocks.
- It does not change `return` semantics.
- It is only ergonomic sugar over the common pattern of handling an `Errable`
  locally and producing a final value.
- It covers the common case where a function handles an `Errable` locally
  instead of propagating it.
