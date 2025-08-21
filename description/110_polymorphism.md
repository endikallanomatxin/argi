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

### Generics

Generics allow for a clean and compact way of doing monomorphization at compile
time.

With generics you can do all static polymorphism, but sometimes it is not the
most ergonomic way. (For example, ...)

### Abstract types

Abstract are like traits.

- Interfaces/traits for dynamic polymorphism.

- Type grouping for function definitions.

(igual debería centrarme más en para qué sirve, más que que implementación
llevan detras)

Si no tuvieramos traits/interfaces/abstract types.



