# Polymorphism

## Use cases

- Homogeneous collections for each different type

- Heterogeneous collections

- Functions that can operate on different types defined at once

- Iterators

- IO sources and sinks
- Databases


## Implementations

1. Estática estructural (tipo Go/anytype pero chequeada):
	Monomorfización, cero overhead de llamada, inlining posible.
	Errores claros en compilación si falta un método/campo.
	Riesgo:
		crecimiento de binario si hay muchas instancias.
	Para:
		Algoritmos genéricos de rendimiento crítico.
		Cuando el tipo concreto es conocido en el punto de instanciación.
		APIs que quieras que se optimicen por inlining/const-prop.

2. Dinámica con vtable (objeto de interfaz):
	Un “puntero gordo” { data_ptr, vtable_ptr }, despacho en runtime.
	Costes:
		indirecta, no-inline por defecto, gestionar ownership/lifetime del data_ptr.
	Para:
		Listas heterogéneas de “cosas que cumplen X”.
		Cargas de plugins, FFI, separación en módulos con ABI estable.
		Cuando quieres reducir tamaño de código aun pagando una indirecta.

3. Dinámica con tagged_union (suma cerrada)

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

Unifica static y dynamic dispatch bajo el mismo constructo.
Por defecto se monomorfiza, pero se puede convertir en Virtual si se quiere
hacer dinámico at runtime.

### Virtual types (for dynamic polymorphism)

Virtual types: Es para usar Vtable

```
Virtual#(Foo) : Type = (
.data_ptr: *anyopaque      // o inline storage si SBO
.vtable:   *const Foo.Vtbl // tabla de fn ptrs derivada del Abstract
.meta:     Meta            // type_id, flags de ownership, storage, etc.
)
```

Requiere un allocator.

Para que un abstract sea Virtual-safe:

- Sus métodos tienen que tener una sola opción posible de dispatch.

- No puede tener Abstract input fields.

> [!CHECK]
> Esto va a ser especialemente molesto para inputs como allocators, o ints que
> se usan como índice... que usar abstracts viene bien, va a obligar a concretar
> muchas cosas en lugar de hacerlas polimórficas.

Uso:

```
process_foo (f: &Virtual#(Foo)&) -> () := {
    f.vtable.do_something(f.data_ptr, ...)
}
```

