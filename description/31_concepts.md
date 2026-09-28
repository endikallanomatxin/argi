## Approaches to copying

For some types (files, sockets, hardware devices, semaphores, GPU buffers, and
others), defining a copy does not make sense. These values cannot be passed by
value, only by pointer, which makes the choice explicit. Requiring an explicit
copy implementation also makes it possible to manage such types appropriately.

### Working direction

The approach that best fits the rest of the language is:

- `copy()` is the only language-level copy operation.
- Only a type that explicitly implements `ImplicitlyCopyable` is copied
  implicitly when a named value is used where another value is acquired.
- Implementing `InfalliblyCopyable` enables `copy(&value)`, but not implicit
  copying.
- Implementing `FalliblyCopyable` enables an explicit copy that returns an
  `Errable`; it never enables implicit copying.
- If a type is not `ImplicitlyCopyable`, plain use is an error: choose
  `copy(&value)` or explicitly transfer ownership with `~value`.
- The semantic promise of `copy()` is always the same: produce an independent
  value according to the meaning of that type.
- For owning types, this means a deep copy of their data. There is no general
  language-level `shallow_copy()` because it would fragment type semantics and
  introduce accidental aliasing.

This fits better than exposing several operations such as `deep_copy()` or
`shallow_copy()` in the language surface.

Every copy, implicit or explicit, must mean logical independence.
Ownership transfer is never inferred from the type.

```
m1 : Map = ()
m2 = copy(&m1)
```

### Different categories of types

- Owning types

    Their `copy()` usually duplicates the data they own.
    They have `init()` and `deinit()`.
    Examples: `String`, `DynamicArray`, `HashMap`.

- Referencing types (views...)

    They should not pretend to own the data they point to.
    If they implement `copy()`, the copy must preserve the view semantics,
    without silently converting the view into an owner.

> [!BUG] Some types can be both
> (linked list nodes, graph nodes, several types that reference others and own some data)
> How should we handle that?


> [!BUG]
> What happens if you pass an `ArrayView` and it is copied?
> Its underlying data should not actually be copied.
> But if you used `keep` to retain the data through the `ArrayView`, and then
> `copy()` and then call `deinit()` on the original, the reference is lost.
> Perhaps we have not solved anything in our language after all.


Possible solution:

- Types that store the data (`DynamicArray`) implement `copy()` by duplicating
  their data.

- Types that are views (`ArrayView`) either do not implement `copy()`, or
  implement it with explicit retained-view semantics.

    Consider thread safety: two possible variants:
    - `SharedView` with an atomic counter (multi-threaded).
    - `LeasedView` with a non-atomic counter (single-threaded).
