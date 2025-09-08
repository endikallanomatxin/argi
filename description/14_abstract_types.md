# Abstract types

- Permiten definir qué funciones deben poder llamarse sobre un tipo.

- Obligan a especificar explícitamente qué tipos subyacen al abstract type.

- Permiten definir un tipo por defecto, que será el que se inicialice si se usa
  como tipo al ser declarado.

- NO permiten definir propiedades (Para evitar malas prácticas)

- Se pueden componer.

- Se pueden extender fuera de sus módulos de origen.


## Declaración

En el cuerpo del abstract, se pueden usar los siguientes tipos:

- Sub: El tipo que implementa el abstract.
- Super: El tipo abstracto en sí.



Así se declara un abstract:

```
Animal : Abstract = (
	-- Las funciones se definen con la sintaxis de currying.
	speak(_) := String
)

speak (d: Dog) -> (s: String) := {
	return "Woof"
}

-- Requiere manifestación explícita de la implementación.
Animal canbe Dog

-- Permite definir un valor por defecto.
Animal defaultsto Dog
```

```
Addable : Abstract
= (
	operator +(_, _) : _
)
```

To use with generics:

```
List#(t: Type) : Abstract
= (
	operator get[](_, _) -> (t)
	operator set[](_, _, t) -> ()
)

List#(t) canbe DynamicArray#(t)
List#(t) canbe StaticArray#(t, Any)
```

To compose them:

```
Number : Abstract = (
	Addable
	Substractable
	Multiplicable
	...
	-- You can mix functions and other Abstract here.
)
```

> [!CHECK]
> Si defines una función que toma un par de Abstracts, ints por ejemplo, tienen
> que ser el mismo tipo? Como se desambigua eso?


## Implementation

Dos implementaciones posibles (se elige automáticamente):

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
	
	> [!CHECK]
	>
	> Cuando se da este caso, igual habría que pasar un allocator? Antes de
	> llamar a la función?
	>
	> Igual se podría hacer que hubiera un tipo Unknown o Union(a, b, c) o
	> lo que sea, que no cumpla la interface, y que haya que invocar algun
	> proceso que lo convierta en una interface y ahí se mete el allocator.



> [!CHECK] Vtables with multiple dispatch?



Estático (monomorfización, cero overhead):
fn sum_area<T: Shape>(xs: []T) -> Float { … }
Dinámico (vtable):
fn draw(x: dyn Shape) { … }
