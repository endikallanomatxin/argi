# Errors

Errors have nominal reasons and explicit propagation. Fallibility does not
require tracing: a diagnostic boundary can explicitly add context using a
caller-provided tracer. Both forms use the same result and cleanup rules.

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

## Error values and results

```rg
Error := #(.reasons: Type) (.reason: reasons)

ErrorWithTrace := #(.reasons: Type) (
    .reason: reasons
    .tracer: $&Virtual#(ErrorTracer) = capture_error_tracer(.location = error_location_id())
)

Errable := #(.t: Type, .reasons: Type, .error_type: Type = Error#(reasons)) (
    ..ok t
    ..error error_type
)
```

An `Error` contains only a reason from a finite payloadless choice. It has no
tracer, allocation or borrowed diagnostic storage. `ErrorWithTrace` also retains
a reference to the original virtual tracer; the tracer must outlive the error.
Trace entries belong to the tracer, rather than to the error's own storage.

`Errable#(T, Reasons)` uses ordinary errors. A traced result uses
`Errable#(T, Reasons, ErrorWithTrace#(Reasons))`. There is one success/error
choice protocol, with the same matching, ownership and cleanup behavior.

The shorthand outputs `-> !T` and `-> !!T` create a single `result` output and
infer its reasons from the body. They select ordinary and traced errors,
respectively. `Errable#(T)` also requests inferred ordinary reasons.

```rg
read_value := () -> !Int32 {
    result = ..error (.reason = ..invalid_format)
}

load_value := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!Int32 {
    assume error_tracer
    value ::= read_value()!! "loading configuration"
    result = ..ok value
}
```

A contextual `..error (.reason = ..invalid_format)` constructs the destination's
payload. In a traced result its ordinary `.tracer` default acquires the lexical
`error_tracer` and records the origin. It does not manufacture a noop tracer.
An explicitly supplied tracer overrides that default. A body's assumptions do
not apply to output defaults, which execute before entering the body.

Both output forms accept defaults, for example `-> !Void = ..ok Void()`.
Reaching the end or using a bare `return` retains the initialized result;
propagation replaces it with an error. An output without a default still needs
initialization. Defaults participate in reason inference.

Core allocation, collection, numeric, text and I/O operations generally return
ordinary errors. Their allocator, FFI, stream and other capabilities remain
independent of diagnostics. EOF remains an ordinary reader outcome, not an
error. Diagnostic operations such as test assertions retain traced errors.

## Propagation

`!` and `!!`:
- short-circuit
- execute `defer`s
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

`!` forwards the existing payload without adding context or acquiring a tracer.
A traced payload stays traced. Propagating it into an ordinary result is rejected;
propagating an ordinary payload into a traced result also requires explicit promotion.
Reason subsets can widen without changing the payload's trace mode.

`!! "context"` explicitly promotes an ordinary error using the lexical
`error_tracer`, or appends context to its existing tracer. It requires a traced
output and an ordinary lexical `error_tracer` value. The operand runs once;
the context expression runs only on failure. If the error is already traced,
its original tracer is retained even when the caller supplies a different one. A tracer
that retains the context copies it, so the entry does not borrow a temporary
string. A tracer that emits the entry immediately can use the text during the
call.

### Reporting and returning

`expr!!!` accepts an `Errable` with either error payload. It evaluates the operand once and
moves the success payload out as `T`. On error it reports the error (including its trace when present)
through the ordinary reachable writer and returns from the containing function.
It is shorthand for recovery whose error branch reports and executes a bare
`return`, not propagation into the function's Errable output.

The enclosing function's output defaults and explicit assignments determine its
return value. Normal owner and defer cleanup runs on that return. A reporting
failure is discarded rather than recursively reported. Functions that use this
operator require the same writer capability as ordinary error reporting.
Reporting and returning with `!!!` is forbidden inside a deferred action; use
local `handle` recovery there so all remaining cleanup still executes.
`!` and `!! context` retain their propagation behavior.

An optional block after `!!!` runs only on failure, after reporting and before
the containing function returns:

```rg
main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    write($&system.terminal&.stdout, "ready\n")!!! { status_code = 1 }
}
```

Success still yields the unwrapped payload without executing the block. The
block has its own lexical scope and normal cleanup; its assignments to output
bindings determine the containing function's return value. A reporting failure
does not prevent this block from running. Both forms of `!!!` remain forbidden
inside deferred actions; use explicit local `handle` recovery there.

In an `if`, `while`, `for`, or `match` header, square brackets disambiguate an
attached error block from the control statement's body:

```rg
if [ready()!!! { status_code = 1 }] { do_work() }
```

A no-result `main` exits with `0`, including when `!!!` returns early. Use an
explicit `.status_code: Int32` output to select another exit status. `main`
returning an Errable has no special entry-wrapper support.

## Error tracing

`ErrorTracer#(Tracer)` is a contract for the tracing policy:

```rg
ErrorTracer#(.Tracer: Type): Contract = (
    .add_context: (.self: $&Tracer, .location: SourceLocationId, .context: StringView) -> ()
    .reset_context: (...) -- infallible: clear retained context and reuse storage
    .report: (...)  -- write a trace; may return an I/O error
)
```

`!` never calls `add_context`. `!! "context"` calls it with the location
and context, while direct traced construction records its origin. `add_context` cannot return an error: propagation must
still succeed when tracing cannot retain or emit an entry. A policy may
allocate or write during `add_context`, but must handle those failures internally.
`report` resolves locations and writes the trace; it may return an I/O error.
The capability has type `$&Virtual#(ErrorTracer)`. A tracer may
be supplied through an explicit `error_tracer` input or lexical `assume`.
Intermediate functions must declare that input to forward the caller's tracer;
there is no propagation through undeclared parameters. The input is required
and has no default. To disable tracing explicitly, enable
`assume error_tracer ::= $&noop_error_tracer` in the calling scope.
Compile-time entry bodies create their own local noop tracer instead of borrowing
the program's mutable global storage:

```rg
assume error_tracer ::= NoopErrorTracer() | to_virtual#(ErrorTracer)($&_) | $&_
```

This capability selects the tracer when a traced error is created or a plain
error is explicitly promoted. Later context and reporting use its retained reference. Returning an error that retains a
function-local tracer is rejected by ordinary reference lifetime rules. A tracer
input keeps that storage in the caller instead, even under a different local
`assume error_tracer`:

```rg
assume error_tracer ::= FixedSizeErrorTracer(
    .buffer = view($&zeroed#(.t: [4096]UInt8)()),
) | to_virtual#(ErrorTracer)($&_) | $&_

run()
```

The positional comptime argument of `to_virtual#(ErrorTracer)` selects the
contract. Alternatively, a declared `$&Virtual#(ErrorTracer)`
capability type permits `to_virtual($&_)` through contextual inference. The
concrete tracer and virtual wrapper temporaries remain alive for the enclosing
`assume` scope. The capability is still a pointer to the virtual wrapper.

`FixedSizeErrorTracer` borrows an initialized byte view supplied by its caller.
Construction is infallible and does not allocate. Callers may supply a local
array, a slice, or storage obtained from an allocator. The buffer must remain
valid for the tracer's lifetime; cleanup does not free or invalidate it.
Headers are copied as bytes, so the buffer requires no additional alignment.
Trace entries, including copies of `!!` context text, occupy that buffer
without allocation. Each slot copies at most 128 context bytes;
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
them to filenames, lines, and source text when `report` runs. Error values
therefore need neither source strings nor an allocator.

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

Tracer initialization and reporting do not require a separate diagnostic
capability merely because a supporting operation can fail. `report` returns
ordinary I/O errors. Reporting never recursively reports its own failures;
the caller chooses whether to propagate, inspect or ignore them.

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

`source_location(.id)` resolves a recorded ID to immutable source metadata;
IDs that were not produced by `error_location_id()` abort.

Current direction for reason inference:
- The signature still spells out the complete declared set.
- `-> !T` and `-> !!T` allow `.reasons` to be omitted for a
  single `result` output.
- `Errable#(T)` without `.reasons` is also accepted in explicit function
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

```rg
my_thing := fallible() handle error, value {
    match error.reason {
        ..file_not_found {
            value = 0
        }
        ..permission_denied {
            report_error(.err = &error)!
            value = 1
        }
    }
}
```

The recovery form converts `Errable#(T, Reasons)` into `T`.

Semantics:
- `handle` is syntactic sugar specific to `Errable`.
- The expression on the left must have type `Errable#(T, ...)`.
- `value` is the shared result slot.
- If the `Errable` is `..ok x`, then `value = x`.
- If it is `..error(...)`, the block runs with `error` bound to the complete
  error payload.
- Use regular `match` on `error.reason` inside the block.
- The block does not return a value specially; it only assigns to `value`.
- The complete construct produces `value`.
- The compiler requires `value` to be initialized on every path through the
  error block that continues past the handler. Paths that return, abort, or
  propagate an error do not need to initialize it.

Motivation:
- It does not introduce a new `match` form.
- It does not introduce value-returning blocks.
- It does not change `return` semantics.
- It is only ergonomic sugar over the common pattern of handling an `Errable`
  locally and producing a final value.
- It covers the common case where a function handles an `Errable` locally
  instead of propagating it.

The operand is evaluated once. Success transfers its payload into the result;
error handling binds the complete error payload only inside the handler. The
result and error names must differ. Handler-local declarations and defers have
ordinary block lifetimes, and `return`, `abort`, and propagation retain their
ordinary meaning. Owning results are moved out of the construct; `handle` does
not make them implicitly copyable. Generic function bodies support the same
form. The result binding is private to the construct and cannot be used later
by its handler name.

### Handling without a result

Omit the value binding to handle an error and continue without recovering a value:

```rg
save() handle error {
    report_error(.err = &error)!
}
continue_work()
```

`expr handle error { ... }` evaluates an Errable operand once. On success it
releases the success payload without running the block. On error it binds the
complete error payload, runs the block, and continues after normal block exit.
This variant produces no recovered value (its expression type is Void).
Both forms keep `return`, `abort`, `!`, and other control transfers relative to
the enclosing function or loop; a handler is an ordinary lexical block, not a
new function. Owned payloads and handler locals receive ordinary cleanup on
normal continuation and on control transfers.

The ordinary `add_context` helper accepts a `StringView`; `add_context_text`
accepts zero-terminated text. Both receive the tracer capability as an ordinary input and call its
scoped operation. Direct operations use `ErrorTracer#(T).add_context(...)`,
`reset_context` and `report`; virtual calls use `ErrorTracer#()` instead.
