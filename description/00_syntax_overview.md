# Syntax overview

## Comments

`--` starts a comment that continues to the end of the line:

```rg
-- A comment
answer : Int32 = 42 -- A comment after a declaration
```

> [!IDEA]
> Multiline comments could enclose longer notes, including Markdown. The
> original proposals were `--- ... ---` and a nestable `--* ... *--` form.
> Their delimiters and nesting rules remain open.

> [!IDEA]
> Documentation comments could use a distinct form such as `---` before a
> declaration. This conflicts with one proposed multiline delimiter, so the
> syntax and whether documentation comments carry Markdown need a decision.

## Declarations

`:` declares a constant and `::` declares a mutable variable. The type may
be written or inferred from the initializer:

```rg
answer : Int32 = 42
count :: Int32 = 0
next := answer + 1
total ::= 0
```

> [!QUESTION]
> Should identifiers accept Unicode letters? An editor could let users type
> `\delta` followed by Tab to insert `δ`; that shortcut would be editor
> behavior, not language syntax.

`=` assigns a new value to an existing mutable place.

> [!IDEA]
> Support simultaneous assignment such as `x, y = y, x`. Define when the
> right-hand sides are evaluated and how moves and cleanup work.

## Arithmetic

Multiplication, division, and modulo (`*`, `/`, `%`) bind more tightly than
addition and subtraction (`+`, `-`). Operators within either tier associate
left to right. Thus `index * stride + header_size` adds the header after
multiplying the index, and `total - used - reserved` subtracts both amounts.
Arithmetic binds more tightly than comparisons.

Square brackets group exactly one expression: `[total + extra] * scale`
evaluates the addition before multiplication. Grouping creates neither a value
container nor a lexical scope. It preserves the expression's type, contextual
literal typing, ownership, and place identity, so `$&[value]` borrows the same
place as `$&value`.

An opening bracket at the start of an expression groups it; a bracket after an
expression indexes it. For example, `values[[index + 1] * stride]` groups part
of an index, while `[values][index]` indexes a grouped array. Empty brackets
and comma-separated expressions are not grouping constructs.

Parentheses retain their struct, list, array, and input syntax. Braces retain
lexical blocks and do not gain an implicit result from grouping.

Pipes retain call/postfix precedence above multiplication and addition. Group
whole calculations or right-hand arithmetic with square brackets; see
[pipe evaluation](40_functions.md#pipe-evaluation-and-placeholder-scope).

## Types and values

Named structs and choices declare types. Struct fields use `.name`, and
choice options use `..name`:

```rg
Point : Type = (
    .x: Int32
    .y: Int32
)

point ::= Point(.x = 3, .y = 4)
```

See [Types](10_types.md), [Structs](11_structs.md), and
[Choice](12_choice.md).

## References

`&place` borrows a read-only reference; `$&place` borrows a mutable one.
Postfix `&` dereferences a reference:

```rg
read(.point = &point)
change(.point = $&point)
point_ref : &Point = &point
x := point_ref&.x
```

`&Point` is a read-only reference type; `$&Point` is its mutable counterpart.
References cannot be null. An optional reference uses `?&Point`. Reference
arithmetic is not allowed. Low-level address calculations use
`UIntNative(.value = reference)`. A calculated address becomes a reference
only through a core operation that establishes its validity root.

References are checked when used and do not keep their referent alive. See
[References and borrowing](32_references.md) and [Nullability](51_nullability.md).

> [!QUESTION]
> Can a `$&T` reference be passed to a function expecting `&T` directly,
> or should the caller explicitly create a read-only reference?

## Code blocks

Braces `{ ... }` enclose a block with its own lexical scope. Variables
declared inside a block are not available after it ends. Function bodies,
conditionals, and loops all use blocks.

> [!IDEA]
> Some blocks could restrict access to outer bindings, like a function's
> explicit inputs. A callable block form would need its own capture and
> invocation rules.

## Functions and calls

Functions declare named input and output fields. The body assigns the output
bindings; `return` exits without a separate result expression:

```rg
add(.left: Int32, .right: Int32) -> (.sum: Int32) := {
    sum = left + right
}

result ::= add(.left = 2, .right = 3)
```

Calls may use named or positional arguments. A single output field yields
its value; multiple output fields yield a structure. The pipe operator uses
`_` to mark where its left-hand value enters a call:

```rg
result ::= 2 | add(.left = _, .right = 3)
```

See [Functions](40_functions.md), [Function arguments](41_function_args.md),
and [Multiple Dispatch](131_multiple_dispatch.md).

## Construction and cleanup

A type may declare `T init(...)` to return a constructed value and define
`T deinit(...)` to clean up a live value. Both operations are optional. `T(...)`
uses a visible constructor when one is defined; its result is `T` or
`Errable#(.t: T, .reasons: R)` when construction can fail.
Local values that need cleanup are cleaned at scope exit.

See [Initialization and deinitialization](30_initialization_and_deinitialization.md),
[Copying and moving](33_copying_behaviour.md), and
[Argi safety model](34_safety_model.md).

## Compile-time parameters

`#(...)` declares compile-time parameters, and a call supplies concrete
arguments with the same notation:

```rg
Array#(.n = 4, .t = Int32)
```

See [Compile-time parameters](132_generics.md).

## Modules

`import("...")` binds another module to a name. An import path is resolved
during compilation:

```rg
math := import("./math")
math.solve()
```

See [Modules and project layout](02_modules.md).

## Control flow

`if` chooses a branch from a condition; `match` chooses a case of a choice
value. `while` repeats while its condition holds, and `for` traverses an
iterable:

```rg
if ready { status = 1 } else { status = 0 }

match direction {
    ..north { status = 1 }
    ..south { status = 2 }
}

while remaining > 0 { remaining = remaining - 1 }
for & item in values { sum = sum + item& }
```

Each braced body has its own lexical scope. See [Control flow](44_control_flow.md).
