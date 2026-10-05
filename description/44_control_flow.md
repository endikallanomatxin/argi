# Control flow

## Conditionals

### If

`if` selects a branch from a `Bool` condition. An `else` branch is optional;
`else if` tests another condition when the earlier ones are false.

```rg
if value == 2 {
    handle_two()
} else if value == 3 {
    handle_three()
} else {
    handle_other()
}
```

### Match

`match` selects a case of a choice value. Each case has its own scope and
finishes without falling through to the next case. A payload can be bound
with the same access modes used elsewhere:

```rg
match value {
    ..some payload { use(.value = payload) }
    ..none { handle_empty() }
}
```

- `payload` binds by value.
- `& payload` binds a read-only reference.
- `$& payload` binds a mutable reference.
- `~ payload` transfers the value.
- `_` ignores the payload.

> [!IDEA]
> A future conditional form could apply an operator to several cases, such
> as testing one value against several `==` operands. Jai explores this with
> a form like:
>
> ```rg
> if value == {
>     case 1 { handle_one() }
>     case 2 { handle_two() }
>     case 3 { handle_three() }
> }
> ```
>
> The syntax and its relation to `match` have not been chosen for Argi.

## Loops

### While

`while` repeats its body while its condition is true. `break` exits the
nearest loop; `continue` starts its next iteration.

```rg
while remaining > 0 {
    remaining = remaining - 1
}
```

> [!IDEA]
> A `loop { ... }` form could express a loop without a condition, ending
> when its body executes `break`. The syntax has not been chosen.

### For

`for` traverses an `Iterable`. The iterable creates an `Iterator`, whose
`has_next` and `next` operations manage traversal state. The element access
mode selects the corresponding iterable contract:

| Form | Required contract | Element type |
| --- | --- | --- |
| `for item in value` | `Iterable#(.t: T)` | `T` |
| `for & item in value` | `ROPointerIterable#(.t: T)` | `&T` |
| `for $& item in value` | `RWPointerIterable#(.t: T)` | `$&T` |
| `for ~ item in value` | `OwningIterable#(.t: T)` | owned `T` |

`for ~ item in value` consumes the complete collection once through
`to_owning_iterator(.value: Self)`. The source becomes moved, including for an
empty collection. The iterator owns all undelivered elements; each `next`
transfers one element to the body binding. The binding has ordinary lexical
cleanup and may itself be moved elsewhere. `continue` cleans the current body,
while `break`, `return`, and error propagation additionally destroy remaining
iterator-owned elements and release its storage. Iterator cleanup happens before
leaving the loop's scope. DynamicArray and Deque preserve logical element order.
No backing allocation or element copy is needed for consuming traversal.

Each contract creates an `Iterator#(.t: element_type)` through
`to_iterator`, `to_ro_pointer_iterator`, `to_rw_pointer_iterator`, or
`to_owning_iterator`,
respectively. A `for` loop accepts an iterable, rather than an iterator
directly.

```rg
Iterable#(.t: Type) : Abstract = (
    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)

ROPointerIterable#(.t: Type) : Abstract = (
    to_ro_pointer_iterator(.value: &Self) -> (.iterator: Iterator#(.t: &t))
)

RWPointerIterable#(.t: Type) : Abstract = (
    to_rw_pointer_iterator(.value: $&Self) -> (.iterator: Iterator#(.t: $&t))
)

Iterator#(.t: Type) : Abstract = (
    has_next(.self: &Self) -> (.ok: Bool)
    next(.self: $&Self) -> (.value: t)
)
```

```rg
for item in Range(.start = 1, .end = 10) {
    use(.value = item)
}

for & item in values {
    inspect(.value = item)
}
```

Iteration by value is conceptually equivalent to creating an iterator and
repeatedly calling `has_next` and `next`:

```rg
it ::= to_iterator(.value = &values)
while has_next(.self = &it) {
    item ::= next(.self = $&it)
    use(.value = item)
}
```

> [!IDEA]
> List comprehensions could build a collection from an iteration. Possible
> syntaxes include an expression followed by its generator, or a leading
> `for` that makes the iteration visible first:
>
> ```rg
> evens ::= (i * 2 for i in Range(.start = 1, .end = 10))
> evens ::= (for i in Range(.start = 1, .end = 10) { yield i * 2 })
> evens ::= (for i in Range(.start = 1, .end = 10); i * 2)
> ```
>
> The syntax and eager or lazy behavior are undecided.

> [!IDEA]
> An enumeration adapter could expose both an element and its index in a
> `for` loop. Iterator adapters such as `map`, `filter`, `zip`, and sliding
> windows could compose traversal without changing the `for` contract.

> [!IDEA]
> A broadcasting operator could apply a function element by element to a
> collection, as Julia's dotted calls do. Its syntax, result type, and
> relationship to iterators remain open.
