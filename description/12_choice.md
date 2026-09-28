# Choice

There are two related layers:
- `choice` with payloads, as a closed tagged union
- standalone `choice options`, which can be composed into open or closed `choices`

## Choice with payload

The payload of a variant can be any `Type`, not just a struct.

```rg
MaybeInt : Type = (
    ..none
    ..some Int32
)

SpanOrEnd : Type = (
    ..end
    ..span (.start: UIntNative, .end: UIntNative)
)
```

The canonical construction syntax is prefix notation:

```rg
a ::= ..none
b ::= ..some 123
c ::= ..span (.start = 3, .end = 8)
```

`..variant expr` consumes the complete payload expression. For example,
`..some a + b` means `..some (a + b)`.

If the payload is a struct, `..variant (...)` is not a special variant call;
it is simply `..variant <expr_struct_literal>`.

## Match and payload access

`match` binds the payload using its actual type:

```rg
match b {
    ..none {
    }
    ..some n {
        use n
    }
}

match c {
    ..end {
    }
    ..span s {
        use s.start
    }
}
```

Payload bindings can declare their access mode explicitly in the pattern:

```rg
match value {
    ..some payload {
        use payload
    }
}

match value {
    ..some & payload {
        use payload&
    }
}

match value {
    ..some $& payload {
        payload& = other_value
    }
}

match value {
    ..some ~ payload {
        consume(payload)
    }
}
```

Rules:
- `payload` is a by-value binding.
- `& payload` is a read-only reference binding of type `&T`.
- `$& payload` is a mutable reference binding of type `$&T`.
- `~ payload` moves the payload; if the scrutinee is an existing binding,
  `match` consumes it.
- `_` ignores the payload.

This follows the same general access mode model as the rest of the language:

- `name` binds by value.
- `& name` binds a read-only reference.
- `$& name` binds a mutable reference.
- `~ name` binds by move.
- `_` ignores the payload.

Additionally, `choice_value..variant` directly projects the typed payload of that
variant after control flow has established that it is active:

```rg
if is(b, ..some) {
    n ::= b..some
}

if c == ..span {
    print(.value = c..span.start)
}
```

If the variant has no payload, `choice_value..variant` is an error.

## Choice options

A standalone option is declared at module scope:

```rg
..file_not_found
..permission_denied
```

Each option:
- is nominal
- has a unique numeric ID assigned by the compiler
- can belong to several `choices`

## Open choices

They are formed from closed lists of options:

```rg
reason : (..file_not_found, ..permission_denied) = ..file_not_found
```

This is especially useful for:
- error reasons
- exhaustive sets of states
- composing APIs that propagate subsets into supersets

## Access and checks

Variant check:

```rg
if is(.value = x, .variant = ..ok) {
}

if is(x, ..ok) {
}

if x == ..ok {
}
```

`is` accepts the nominal form and positional form `(value, variant)`. `==` and
`!=` can be used directly with a `..variant` literal when the other side already
has a `choice` type; this compares only the tag and ignores the payload.

These checks refine control flow. In the true branch of a positive check, the
variant is active and the others are discarded; in the false branch, only the
tested variant is discarded. A negative check reverses the two branches. If
exactly one alternative remains, the compiler can activate it; otherwise it
does not choose an alternative.

Direct payload projection requires that prior check:

```rg
if is(x, ..ok) {
    payload ::= x..ok
}
```

Outside a `match` case or a branch that has checked the tag, `x..ok` is a
safety error. Projection is structural access to the active payload, not a
checked unwrap or an operation that silently changes the variant.

`match` remains the main tool when you need to cover the complete closed set.

> [!IDEA] Compact choice storage in `core`
> Explore a generic `CompactChoiceStore` / `PackedChoiceStore` abstraction in
> the core library rather than adding a choice-storage builtin to the compiler.
> The store could keep a tag plus a fixed inline payload area, with variants
> that do not fit using an overflow/extra storage representation.
>
> Comptime/reflection could derive the layout and typed accessors. The aim is
> to keep common variants compact, accepting extra storage and access costs for
> larger ones. Validate the pattern in a concrete use such as AST-like storage
> before extracting a generic abstraction.
