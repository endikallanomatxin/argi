## Source of confusion

The model: Stack with simple mental model and automatically managed vs. heap
memory that has to be managed manually.

The issue: References to data on the heap break the mental model of working
with the stack only.

Typical example: Shallow copying a struct with pointers to heap data.
(Let's call it the RefStruct / maybe descriptor is clearer?)
In many languages (C, Zig, odin...), everything is passed by value.
So when you pass by value a RefStruct, you get a shallow copy.

This sort of situation is where most memory errors occur, and it's where memory
management strategies vary the most between programming languages.

It causes:
- Unwanted side effects.
- Double free errors.
- Use after free errors.
- Memory leaks.

```
m1 : Map = ()
m2 := m1
m2 | put($&_, "key", "value") -- Cambia el original

m1 | deinit($&_)
m2 | deinit($&_) -- Double free error
```

In manually managed laguages, to avoid that you usually need to know about the
underlying implementation, breaking abstraction.

In languages with automatic memory management (GC, ref counting...), the
problem is avoided, but at the cost of performance and control.

What we want:
Manual memory management that is easy to use and hard to misuse.
(Somehow automatic, but at compile time, not runtime.)
(similar to mojo, which is similar to rust but simpler)


## Solution

All values will be automatically deinitialized after their last use.

All types must implement init() and deinit() methods.

Also, passing a value by value must mean getting an independent value.

That means:

- If a type implements `copy()`, assigning it or passing it by value performs
  an implicit deep copy.
- If a type does not implement `copy()`, it cannot be used in value position.
  The compiler should reject it and suggest using `&` or `$&`.
- `deinit()` is still inserted automatically, so the user keeps the stack-like
  mental model for destruction.

This avoids shallow-copy surprises while keeping manual memory management
explicit where a true copy does not make sense.

