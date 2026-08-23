# Virtual types (vtable-based dynamic dispatch)

> “Abstract siempre monomorfiza; si quieres despacho dinámico lo pides explícitamente.”

## Aplicación

* **Colecciones heterogéneas**
* **Cargas de plugins / FFI**: objetos pasados por interfaz estable.
* **Reducción de bloat en el compilado**: una llamada indirecta en vez de N versiones monomorfizadas.
* **Límites claros**: el usuario **elige** cuándo pagar la indirecta.
- **Coste**: 1 carga de puntero + 1 **indirect call**.

Regla de oro:

* “**Hot loop** cerrado en memoria/cómputo” → estático (genéricos).
* “**Fronteras** (IO/FFI/plugins) y heterogeneidad” → `Virtual`.

## Virtual-safety

Un método del `Abstract` es **virtual-safe** si, tras el borrado de tipo:

- **Parámetros y retorno** son **erase-safe**:
  - primitivas/POD, punteros, slices…
  - **Virtual#(X)** (si necesitas otro abstract).
- **No** aparecen tipos abstractos “puros” ni genéricos libres **en la firma**.
- **Sin genéricos en la vtable**: las firmas deben ser **monomórficas** tras borrar.

> Multiple dispatch (MD) **no** es virtual-safe.

## Definición

```argi
Virtual#(.abstract: Abstract) : Type = (
  .data   : $&Any
  .vtable : &Any
)
```

The compiler represents `Virtual#(.abstract: A)` as the identified fat pointer
`{ data, vtable }`. `to_virtual#(.abstract: A)(.value = ref)` verifies that the
concrete referent implements `A`, erases its data pointer, and constructs a
vtable ordered by the requirements in `A`.

Calls using `&Virtual`, `$&Virtual`, or `$$&Virtual` as the requirement's `Self`
argument are lowered to an indirect call through that vtable. Argi's internal
storage-address ABI already gives every concrete implementation an erased,
layout-compatible call shape, so no copying thunk is required for supported
virtual-safe signatures. Primitive/POD/reference inputs and outputs, multiple
outputs, and heterogeneous collections of one Virtual type share this path.

The current handle is borrowed: it does not allocate or own the concrete value.
An owning Virtual form can add allocator/drop metadata later without changing
the dispatch or temporal-envelope rules.

Pointer casts through `Any` preserve provenance. Erasing and recovering the
data pointer therefore cannot hide use-after-invalidation from the temporal
checker.

## Creación

```argi
s :: Rectangle = (1, 2)
vs ::= to_virtual#(.abstract: Shape)(.value = $&s)
```

## Uso

```argi
do_something(.v: &Virtual#(.abstract: Shape)) -> () := {
  draw(.self = v) -- indirect call through Shape's vtable
}
```

`Virtual#(.abstract: Shape)` satisfies the virtual-safe callable surface of
`Shape`; ordinary `Shape` inputs remain statically monomorphized.


## Interoperabilidad y ABI

The vtable order is the declaration order of the Abstract requirements. A
method is rejected at the call site when `Self` escapes by value or through an
output. Generic/free-Abstract signatures and multiple dispatch remain outside
the virtual-safe subset.

Future ABI customization may cover:

- stable exported vtable layouts,
- owning/drop metadata,
- plugin and cross-module ABI versioning.
- ...


> [!IDEA]
> Igual se puede hacer overloadeando `to_virtual`.
> Podría ser Virtual una especie de Abstract que se puede implementar?


---

## Multiple dispatch compatibility

> [!TODO] Explorar vtables con multiple dispatch.
> Podría hacerse como un grafo de decisiones de dispatch y que se aplique
> curriando funciones.
> Explorar la idea.
