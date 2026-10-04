# References and borrowing

`&T` grants read access to a `T`; `$&T` grants read and write access. Borrowing
is explicit at the use site:

```rg
inspect(.value = &x)
change(.value = $&x)
```

Borrowing does not by itself extend existing storage or acquire its cleanup
responsibilities. Returning references to bounded local storage can transfer
that storage to the caller, as described below. A `$&T` may reach a place whose
current value has such responsibilities; mutating or deinitializing that value
changes the place.
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

## Returning references to local storage

A function may return safe references to local values when the storage that
must survive has a statically bounded shape. The compiler constructs those
values in storage supplied by the caller rather than the callee's stack.
The retained storage includes backing arrays, referenced local owners, and
local capabilities required by delayed cleanup. Internal addresses remain
stable; promotion neither allocates on the heap nor grants allocation receipts.

Cleanup follows the receiving scope. A receiving value's destructor runs
before its retained storage is destroyed, and retained values are destroyed
once in reverse construction order. Copies of a reference do not independently
extend that storage's lifetime. Dependencies borrowed from the caller still
need to remain valid, and explicit destruction still invalidates references.

Branches do not require dynamic storage when every alternative has a bounded
shape. The compiler reserves the alternatives and tracks which values were
initialized. Nested direct calls may forward bounded retained storage through
the caller's result.

An unbounded number of retained values requires explicit dynamic storage.
For example, repeatedly creating locals and appending their references to a
`DynamicArray` does not make the array own those locals: its allocation stores
the references. Allocate the referenced values explicitly when their number
cannot be bounded at compilation time. The compiler diagnoses unsupported
retention instead of introducing implicit heap allocation.

> [!IMPLEMENTATION]
> Promotion currently supports finite direct-call frames. Recursive retention,
> repeatedly constructed retained locals, retaining calls inside loops, and
> virtual methods returning retained local storage are rejected.

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
reference to it can survive in a function result through bounded caller-owned
storage; otherwise its expression lifetime applies.
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
