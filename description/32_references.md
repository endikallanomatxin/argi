# References and borrowing

`&T` grants read access to a `T`; `$&T` grants read and write access. Borrowing
is explicit at the use site:

```rg
inspect(.value = &x)
change(.value = $&x)
```

Borrowing does not by itself extend existing storage or acquire its cleanup
responsibilities. A function cannot return a reference that depends on storage
ending when it returns. A `$&T` may reach a place whose current value has cleanup
responsibilities; mutating or deinitializing that value changes the place.
Aliases are checked when they are used. Mutable references may alias in
sequential code: `$&T` does not imply exclusive access or `noalias`.
Concurrency requires additional rules.

In [Rust](https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html),
an active mutable borrow excludes other references to the same value. Argi
permits multiple `$&` and mixed `&`/`$&` aliases in sequential code; it
checks whether a reference is still valid when the reference is used.

## Validity

A reference is usable only while its target storage and any resources it
depends on remain valid. Its binding can stay in scope after a dependency
ends; using it then is an error. Returning or storing a reference requires it
to remain valid for every later use. Borrowing an expression result creates
temporary storage subject to the same rule, as described below.

References may point to projected places such as a struct field or an array
element:

```rg
&record.field
$&array[i]
```

The prefix applies to the whole place. Postfix `&` dereferences a pointer, so
`array&[i]` means `(array&)[i]`; it is not another borrowing mode. A container
operation that moves or replaces an element may invalidate a reference to
that element even while the container remains live.

## Returning values and references

A function output cannot depend on a local storage generation that ends when
it returns. This includes references to local variables, by-value input slots,
local arrays, and temporary expression results. Wrapping a reference in a
struct, choice, virtual value, or owning container does not extend its lifetime.
The rule also applies to hidden dependencies: an `Allocation` cannot escape
with a local deallocator, and an `Error` cannot escape with a local tracer.

Return an owned value when the caller should receive ownership. If the result
must borrow storage, create the owner in the caller and pass its reference to
the helper:

```rg
NumberBox: Type = (.value: Int32)

number(.box: &NumberBox) -> (.result: &Int32) := {
    result = &box&.value
}

main() -> () := {
    box ::= NumberBox(7)
    reference ::= number(&box)
}
```

Borrows derived from inputs or globals remain valid while their original
owners and resources remain valid. Returning an owner transfers its ordinary
cleanup responsibilities; references inside that owner must still obey the
same lifetime rule. Returning an owner together with a reference to its local
slot does not establish an address-stability or pinning guarantee.

Large values may use destination passing or an indirect return as an ABI
choice. This does not extend local lifetimes or permit references to local
storage to escape. There is no implicit heap allocation or hidden storage
retention for borrowed outputs.

## References to expression results

An expression that produces a value can be borrowed directly. Argi gives the
result storage as though it had first been assigned to a temporary variable:

```rg
read(.number = &7)
read_mut(.number = $&NumberBox(.value = 9).value)
```

The rule also applies to constructor calls and values passed through nested
calls or pipes. Taking a reference does not turn the constructed value into a
pointer value or transfer its cleanup responsibilities to the reference.
The temporary remains alive while the surrounding expression uses it, then
is cleaned up, including on short-circuit and loop-condition exits. A
reference to it cannot escape through a function result.
Moving the temporary value into a destination instead transfers its cleanup
responsibilities there.

An `assume` declaration can bind a constructed temporary for its local scope:

```rg
assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
```

The allocator is cleaned up at scope exit, and its reference cannot escape
that scope. References held inside the temporary must satisfy the ordinary
validity rules; construction cannot extend their lifetimes.

## References in values

Copying a reference or a non-owning view does not acquire responsibility for
cleaning up its referent. A struct can hold a resource in one field and borrow
through another; the borrowed field must still be valid when it is used. A
view does not gain responsibility for cleaning up backing storage merely
because it is copied.

> [!IDEA]
> A separate retained-view type could own shared access to backing storage.
> Thread-safe and single-threaded variants may need different ownership
> mechanisms; copying an ordinary `ArrayView` would still only copy its borrow.
