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
Virtual#(A: Abstract) : Type = (
  .allocator: &Allocator
  .data_ptr : &Any        -- fat pointer al dato
  .vtable   : &VTable#(A)
  .meta     : Meta        -- type_id, drop_fn, flags, storage, etc.
)
```

## Creación

```argi
s : Rectangle = (1, 2)
vs := s | to_virtual(_, Shape, system.allocator)
```

## Uso

```argi
do_something (v: Virtual#(Shape)) -> () := {
  v.vtable.draw(v.data_ptr)        -- call virtual-safe method
}
```

O más ergonómico y compatible:

```argi
do_something (v: Shape) -> () := {
  draw(v)
}
```

> [!CHECK] Es buena idea que Virtual#(Abstract) cumpla Abstract?
> Lo hace muy cómodo. Hay que valorar si trae alguna complicación.


## Interoperabilidad y ABI

Pensar en como customizar el funcionamiento de Virtual para que encaje bien con distintos escenarios:

- Especificación del orden de las funciones.
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

