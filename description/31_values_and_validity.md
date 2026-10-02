# Values, places, and validity

A **place** is storage such as `x`, `x.field`, or `array[i]`. It can be
initialized, moved-from, or deinitialized. The place and the value currently
in it are distinct: ending one value does not necessarily end the place, and
the place can later hold another value.

A value can carry two different kinds of safety fact:

- **Validity dependencies:** resources that must still be live when the value
  is used. A reference or view usually has such dependencies.
- **Cleanup responsibilities:** resources whose lifetimes end when this value
  is cleaned up. A value may have several, none, or both responsibilities and
  dependencies.

These facts come from how a value was created and what operations it has
undergone.

In [Rust](https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html),
reference lifetimes are part of types, and the type system restricts
conflicting borrows. In Argi, validity dependencies and cleanup
responsibilities belong to the particular value. Its type alone does not
determine which lifetimes it depends on or ends, and cleanup responsibility
does not grant exclusive access to its place.

A value may be used only while every validity dependency it carries remains
live. A dependency does not keep its resource alive.

Reusing the same storage or address does not revive a reference to an ended
lifetime.
