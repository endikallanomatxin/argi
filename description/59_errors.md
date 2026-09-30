# Errors

Errors have nominal reasons, explicit propagation, and a trace of the places
where they were propagated. The trace policy is supplied as a capability.
Propagation is infallible; its memory and I/O costs depend on that policy.

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

An error carries its reason and a small handle to its trace. Trace entries are
held by the configured tracer, not embedded in each error value.

```rg
Error#(.reasons: Choice) : Type = (
    .reason: reasons
    .trace: ErrorTrace
)
```

`.reason` must be a `choice` without payloads. `ErrorTrace` retains a reference
to the original virtual `ErrorTracer`. The bundled policies use a shared log,
so the reference itself is the complete handle.
Creating an error records its origin through that tracer. The tracer must
outlive errors referring to it; clearing its retained context does not end
the lifetime of the error or change its reason.

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
- conditions: `if ready()! { ... }`
- assignments: `cached = load()!`
- standalone statements: `flush()!`

The expression yields the `..ok` value. A named struct remains whole even
when it has only one field. An anonymous one-field payload is unpacked to
that field's value.

`!! "context"` also attaches textual context to the trace entry. A tracer
that retains the context copies it, so the entry does not borrow a temporary
string. A tracer that emits the entry immediately can use the text during the
call.

## Error tracing

`ErrorTracer` is an `Abstract` for the tracing policy:

```rg
ErrorTracer : Abstract = (
    add_context(.self: $&Self, .location: SourceLocationId, .context: StringView) -> ()
    reset_context(...) -- infallible: clear retained context and reuse storage
    report(...)  -- write a trace; may return an I/O error
)
```

`!` calls `add_context` with the propagation location and empty context.
`!! "context"` calls it with
the location and context. `add_context` cannot return an error: propagation must
still succeed when tracing cannot retain or emit an entry. A policy may
allocate or write during `add_context`, but must handle those failures internally.
`report` resolves locations and writes the trace; it may return an I/O error.
The capability has type `$&Virtual#(.abstract: ErrorTracer)`. A tracer may
be supplied through `reach error_tracer`, so intermediate
functions need not list it manually. This capability selects the tracer when
an error is created. Later propagation and reporting use the reference in
that error, even under a different `assume error_tracer`:

```rg
assume error_tracer ::= FixedSizeErrorTracer(
    .allocator = system.page_allocator,
    .size = 64 * 1024,
)! | to_virtual#(ErrorTracer)($&_) | $&_

run()
```

The positional comptime argument of `to_virtual#(ErrorTracer)` selects the
abstract. Alternatively, a declared `$&Virtual#(.abstract: ErrorTracer)`
capability type permits `to_virtual($&_)` through contextual inference. The
concrete tracer and virtual wrapper temporaries remain alive for the enclosing
`assume` scope. The capability is still a pointer to the virtual wrapper.

`FixedSizeErrorTracer` allocates its fixed buffer during fallible `init`.
Subsequent trace entries, including copies of `!!` context text, occupy that
buffer without further allocation. Each slot copies at most 128 context bytes;
longer context is truncated. Buffer space smaller than a complete slot is
unused. A buffer with no complete slots drops every entry.
For a single trace, roughly half preserves the origin and first contexts;
the other half is a ring buffer retaining recent frames. If the trace exceeds
the buffer, `report` shows the beginning, a truncation marker, and the end.
The middle is discarded. When several errors share the buffer, this
implementation may also evict entries belonging to other errors.

Storage isolation between errors is not required. A tracer may interleave
entries from several errors and report shared context, using separators as
appropriate. Retention, truncation, eviction, and loss indicators belong to
each implementation's policy. Reporting either of two errors referring to a
shared-log tracer observes that tracer's retained context, not an isolated
chain belonging to the selected error. Reset followed by propagation of an
older error can therefore make that new context visible through both errors.
Their nominal reasons and original tracer references remain independent of
this diagnostic retention policy. No policy may interpret reused storage as an
old entry or access storage that is no longer valid.

Entries store compact `SourceLocationId` values. Executable metadata maps
them to filenames, lines, and source text when `report` runs. `Error` therefore
needs neither source strings nor an allocator.

`reset_context` clears the tracer's retained diagnostic context and permits
storage reuse. Existing errors remain valid: their reasons and tracer
references are unchanged, and they may still be propagated or reported.
The tracer must recognize handles from before the reset without accessing
stale entries. Later propagation can record new context for those errors;
cleared context is not recovered. Any generations used to distinguish reused
storage are internal to the tracer, not lifetimes of the error value.

`NoopErrorTracer` is another valid policy. It records no frames while keeping
the same infallible propagation interface. Other policies can implement the
same abstract interface.

Tracer initialization uses an already available tracer. At bootstrap, a
`NoopErrorTracer` with program lifetime provides this capability without
allocation. If a new tracer's initialization fails, its error retains the
previous tracer; the partially initialized tracer is never published.

`report` returns ordinary I/O errors, but errors created by the reporting
operation use the program-lifetime `NoopErrorTracer`. Reporting must not
automatically report its own failures or invoke the failing tracer again.
The caller decides whether to propagate, inspect, or ignore a report failure.

> [!IDEA]
> An allocating tracer could retain complete traces, growing storage during
> `add_context`. If allocation fails, it would drop or truncate entries and keep
> propagation infallible.
>
> A streaming tracer could format each entry into a small buffer and flush it
> to a terminal as soon as context is added. This suits a REPL, where seeing
> the trace as execution proceeds may matter more than retaining it for a
> later `report`. Because `add_context` is infallible, write failures during these
> flushes must be ignored or recorded for a later fallible `report`.

Fallible virtual methods receive the reached tracer capability alongside
ordinary arguments, including implementations whose bodies always succeed.
This keeps runtime dispatch consistent when an implementation creates an error.
`source_location(.id)` resolves a recorded ID to immutable source metadata;
IDs that were not produced by `error_location_id()` abort.

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

## Exhaustiveness

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
            report(.trace = &error.trace)!
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
