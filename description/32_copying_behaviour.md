## Copying and ownership

The rule of the language should be:

> Using a value in value position means requesting an independent value.

This keeps pass-by-value semantics consistent with the stack mental model and
avoids accidental aliasing.


## Value position

A value is in value position when it is:

- assigned to another variable
- passed to a function argument declared by value
- stored by value inside another value
- returned by value

In all those cases the semantics should be the same.


## Copy model

If a temporary value is used in value position, it may be moved directly.

If an existing named value is used in value position and the type implements
`copy()`, the compiler may insert an implicit call to `copy()`.

```
m1 : HashMap#(.key: String, .value: Int32) = ()
m2 := m1  -- Implicitly calls copy(m1)
```

The semantic promise of `copy()` is that the result is logically independent
from the original value. For owning heap-based types this normally means a deep
copy of the owned data. The language does not expose a general
`shallow_copy()` operation, because that would make it too easy to break the
intended ownership semantics of a type.

If a type does not implement `copy()`, it cannot be used in value position.
When the user places a non-copyable type in value position, the compiler should
emit an error with a concrete fix:

- use `&` if the callee only reads
- use `$&` if the callee mutates
- implement `copy()` if true value semantics are desired
- or use `~value` if ownership transfer is intended

```
file2 := file1
-- Error: File cannot be copied. Pass it by & or $& instead.
```


## Explicit move

Existing bindings are not moved implicitly by default.

If the programmer wants to transfer ownership out of a binding, that should be
spelled explicitly:

```
consume(.resource = ~file1)
```

After `~file1`, the binding is considered moved and cannot be used again until
it is reinitialized.

This keeps the surface model simple:

- temporary values can flow efficiently through composed expressions
- named values keep copy semantics by default
- ownership transfer from a binding is explicit


## Non-copyable types

Some types do not have a meaningful or safe copy operation:

- files
- sockets
- mutexes
- hardware devices
- GPU buffers
- system capabilities

Those types are not special-cased by syntax. They are simply non-copyable
because they do not provide `copy()`.


## Copyable owning types

Types such as `String`, `DynamicArray` or `HashMap` may choose to implement
`copy()`.

When they do, assigning them or passing them by value means creating an
independent value.

```
arr1 :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 3)
arr1 | push($&_, 1)
arr1 | push($&_, 2)
arr1 | push($&_, 3)
arr2 := arr1

arr2 | push($&_, 4)
-- arr1 remains unchanged
```


## Views and references

Views do not own the data they point to, so they should not silently turn into
owners through normal copy semantics.

If a view type is copyable, its `copy()` must preserve the intended meaning of
that view. It must not pretend to create ownership of the underlying data.

That means the language-level rule stays simple:

- owning types may implement `copy()` to duplicate ownership
- view types may implement `copy()` only if that operation is semantically
  sound for the view itself
- otherwise they are non-copyable and must be passed by reference

> [!TODO]
> Think about how to make it clear that when copying a view or a
> pointer, you are not getting the ownership of the data.
>
> Maybe some types should have a mandatory postfix indicator in their names.
> Like `_v` for views, `_p` for pointers, etc. Maybe it is a bit too noisy.
