# Functions

A function declares named input and output fields. Every field in its
signature has an explicit type. The input fields form one logical input
structure; the output fields form one logical output structure.

```rg
add(.left: Int32, .right: Int32) -> (.sum: Int32) := {
    sum = left + right
}
```

The body reads inputs by name and assigns output bindings by name. An output
without a default must receive a value before the function completes. A
default supplies its value when the body does not replace it:

```rg
main() -> (.status_code: Int32 = 0) := {
}
```

Empty `()` denotes no input or no output. A `return` leaves the function; it
does not carry a separate result expression. Results come from the output
bindings.

## Calls and results

Arguments may be named or supplied positionally in declaration order. A
positional argument cannot follow a named one:

```rg
sum ::= add(20, .right = 22)
```

A call with one output field yields that field's value. The field name can
also be written explicitly, as in `add(20, 22).sum`. A call with several
output fields yields a structure with those fields. A call with no outputs
yields `Void`.

> [!IDEA]
> A destructuring declaration could bind several output fields at once:
>
> ```rg
> quotient, remainder := divmod(7, 3)
> quotient, _ := divmod(7, 3)
> ```
>
> The binding syntax, ignored fields, and interaction with output names
> still need design. Individual fields can already be selected by name.

Inputs passed by value, by read-only reference, or by mutable reference
follow the same rules as other value uses. A named value moves into a
by-value input only with `~`; borrowing is written with `&` or `$&` at the
call site. `$&` permits mutation but does not imply exclusive access.

## Pipe expressions

The pipe operator passes its left-hand value into a call on the right. `_`
marks where that value is used. When the left-hand call has several output
fields, `_` denotes the whole result structure; `_.field` selects one field:

```rg
result ::= 20 | add(.left = _, .right = 22)
sum ::= point | add(.left = _.x, .right = _.y)
is_error ::= value | is(_, ..error)
```

The placeholder may be borrowed explicitly, for example
`value | inspect(.item = &_)` or `value | change(.item = $&_)`.
It may also occupy a positional argument, including one in a built-in call.
Pipes may be chained. The right-hand call must contain a placeholder; the
left-hand value is not silently inserted into an arbitrary argument.

## Function variants

Functions with the same name may have different input types. Dispatch uses
the name and input types, not output types or input field names. An ambiguous
call is an error.

A function may be declared `once` when it is intended to be consumed at most
once from the reachable call graph of the compiled entrypoint.

> [!IDEA]
> Anonymous functions could use the same input, output, and body syntax as
> named functions when passed as values:
>
> ```rg
> apply(.operation = (.value: Int32) -> (.result: Int32) := {
>     result = value + 1
> })
> ```
>
> Captures, lifetime rules, and how such functions are typed remain open.

> [!IDEA]
> An explicit memoization wrapper could cache a function's result for equal
> inputs. It would need rules for side effects, input equality, and the
> ownership and validity of cached results.
