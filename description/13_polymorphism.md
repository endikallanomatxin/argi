# Polymorphism

## Use cases

- Homogeneous collections for each different type

- Heterogeneous collections

- Functions that can operate on different types defined at once

- Iterators

- IO sources and sinks
- Databases


## Implementations

- Static polymorphism through monomorphization.
- Dynamic polymorphism through tagged_unions (closed) or vtables (open).


## Ergonomy constructs

### Multiple dispatch

Permite que operaciones sobre distintos datos tengan el mismo nombre.
(OOP hace esto por objeto, 1 argumento, multiple dispatch lo permite en todos)

### Generics (for parametric polymorphism)

Generics allow for a clean and compact way of doing monomorphization at compile
time.

With generics you can do all static polymorphism, but sometimes it is not the
most ergonomic way.

### Abstract types (for subtype polymorphism)

Unifica static y dynamic dispatch bajo el mismo concepto. Se implementa según
sea necesario. Si es posible monomorfiza, si no, se hace dinámico, con el coste
que conlleva.

