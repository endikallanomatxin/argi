# Copying and moving

Argi keeps the operation selected at a call site independent of the value's
type:

```rg
x          -- normal value use
~x         -- explicitly move a value
copy(&x)   -- explicit duplication
```

A plain use of a named value never changes from copy to move according to its
type. When a context must acquire another value, `x` is accepted when its
type implements `ImplicitlyCopyable`. Otherwise the programmer must choose
`copy(&x)` or `~x`.

[Rust](https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html) may
move a non-`Copy` value when a named variable is passed by value. Argi does
not choose a move from the value's type: a named source moves only with `~`.

> [!IMPLEMENTATION]
> The compiler also permits implicit copies of types it judges trivially
> copyable when they have no explicit `copy` operation, even without an
> `ImplicitlyCopyable` implementation.


## Value-consuming contexts

Examples of contexts that may need to acquire a value are:

- initializing or assigning another binding;
- passing an argument declared by value;
- storing a field or choice payload by value;
- returning a value;
- reading an indexed Place as a value.

For a named value in one of these contexts:

```text
if T implements ImplicitlyCopyable:
    produce an implicit independent copy
else:
    reject the plain use
```

The rejection is not an implicit move. A fresh temporary result may flow
directly into its destination, without an artificial copy or explicit `~`.


## Copy contracts

Copying always creates another value that is logically independent of the
source. Argi separates the contract for copying from permission to insert that
copy implicitly:

```rg
InfalliblyCopyable : Abstract = (
    copy(.self: &Self) -> (.value: Self)
)

FalliblyCopyable#(.reasons: Type) : Abstract = (
    copy(.self: &Self)
        -> (.result: Errable#(.t: Self, .reasons: reasons))
)

ImplicitlyCopyable : Abstract = ()
ImplicitlyCopyable implements InfalliblyCopyable
```

The relationships are:

```text
ImplicitlyCopyable => InfalliblyCopyable
InfalliblyCopyable !=> ImplicitlyCopyable
FalliblyCopyable   => never copied implicitly
```

An infallible but expensive type can implement `InfalliblyCopyable` while
requiring explicit `copy(&value)`. A fallible type such as `String` can
implement `FalliblyCopyable#(.reasons: (..out_of_memory))`; its failure remains
part of `copy`, not a differently named operation.

The language has no general `shallow_copy()`. Copying a value that has a
resource cleanup responsibility must establish independent resources and a
separate cleanup responsibility. Copying a reference or non-owning view
preserves its borrowing limits without acquiring cleanup responsibility for
its referent.

A type may hold resources in some fields and borrow through others. Its
`copy()` must duplicate the resources independently and keep borrowed fields
subject to their original lifetimes.

## Implicit copies

Small scalar types implement `ImplicitlyCopyable`, so this is valid:

```rg
a :: Int32 = 3
b := a
```

Conceptually, the compiler may produce the same result as `copy(&a)`, while
keeping the source usable. Small value structs may opt into the same behaviour
explicitly.

Merely providing an infallible `copy()` is not enough to opt in. Providing a
fallible `copy()` can never opt in because an ordinary value use has no place
to expose the error.


## Explicit copies

Values such as `String`, `DynamicArray`, and maps normally require an explicit
copy, which may fail while allocating independent storage:

```rg
copied_result ::= copy(.self = &original)
match copied_result {
    ..error reason { /* handle the copy failure */ }
    ..ok ~ copied { /* original and copied are independent */ }
}
```

If an element-wise container copy fails part way through, it must destroy the
already copied prefix exactly once before releasing its new backing storage.
The original container remains unchanged.


## Explicit move

Moving a named value is always written with `~`:

```rg
second := ~first
consume(.resource = ~second)
```

The destination receives the value and its cleanup responsibilities without
calling `deinit` at the source. The source binding becomes moved; reading,
moving, reassigning, or cleaning it again is rejected. Unaffected fields of a
partially moved aggregate still require cleanup.
Moving does not redirect existing references to the source's storage.

In particular, this is an error for a non-`ImplicitlyCopyable` type:

```rg
second := first
```

It does not silently become `second := ~first`.


## Non-copyable types

Some resources have no meaningful duplication operation, including files,
sockets, mutexes, devices, and `Allocation`. They implement no copy abstract.
They can be borrowed or moved explicitly:

```rg
inspect(.file = &file)
mutate(.file = $&file)
other := ~file
```

A diagnostic for a rejected plain use should list only valid alternatives. If
the type is copyable it can suggest `copy(&value)` and `~value`; if it has no
copy operation it should suggest borrowing or explicit transfer instead.


## Indexed value access

The access prefix applies to the whole Place:

```rg
arr[i]       -- normal value use; implicit copy only when the item opts in
~arr[i]      -- explicit take, when the collection supports it
```

Borrowed indexing and iteration remain visible at the call site; Argi does not
infer a borrow from a plain value use.
