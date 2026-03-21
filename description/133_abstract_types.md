# Abstract types

Abstract types should be one of the main reusable abstraction mechanisms of the
language. They are primarily for expressing static contracts.

- Permiten definir qué funciones deben poder llamarse sobre un tipo.

- Obligan a especificar explícitamente qué tipos subyacen al abstract type.

- Permiten definir un tipo por defecto, que será el que se inicialice si se usa
  como tipo al ser declarado.

- NO permiten definir propiedades (Para evitar malas prácticas)

- Se pueden componer.

- Se pueden extender fuera de sus módulos de origen.

- Si se usan en la firma de una función, se monomorfiza por defecto, para usar
despacho dinámico en runtime, hay que usar `Virtual#(.a: AbstractType)`.

- Los tipos concretos que implementan un abstract pueden tener parámetros de
  comptime extra, pero tienen que poder mapear explícitamente los parámetros del
  contrato abstracto.


## Declaración

En el cuerpo del abstract, se pueden usar Self como el tipo que lo implementa.


Así se declara un abstract:

```
Animal : Abstract = (
	-- Las funciones se definen con la sintaxis de currying.
	speak(.who: Self) -> (.text: String)
)

speak (.d: Dog) -> (.s: String) := {
	return "Woof"
}

-- Requiere manifestación explícita de la implementación.
Dog implements Animal

-- Permite definir un valor por defecto.
Animal defaultsto Dog
```

> [!CHECK] Valorar default
> Como la sintaxis cómoda para definición de listas al final no se va a dar,
> igual no tiene sentido esto.

```
Addable : Abstract = (
	operator + (.left: Self, .right: Self) -> (.result: Self)
)
```

To use with generics:

```
Indexable#(.t: Type) : Abstract = (
	operator get[] (.self: &Self, .i: UIntNative) -> (.value: t)
)

Resizable#(.t: Type) : Abstract = (
	operator get[] (.self: &Self, .i: UIntNative) -> (.value: t)
	operator set[] (.self: $&Self, .i: UIntNative, .value: t) -> ()
	push (.self: $&Self, .value: t) -> ()
)

DynamicArray#(.t: Type) implements Resizable#(.t: t)
Array#(.n: UIntNative, .t: Type) implements Indexable#(.t: t)
```

To compose them:

```
Number : Abstract = (
    Addable
    Substractable
    Multiplicable
    -- You can mix functions and other Abstract here.
)
```

Cases:

- When a function takes more than one abstract type, types are not assumed to
be the same, to express that, use compile-time-parameters.

    ```
    foo#(.t: Type: ExampleAbstract) (.a: t, .b: t) -> (.r: t) := { ... }
    ```

    Todas las llamadas a funciones que usan abstracts se podrían expresar
    usando generics en realidad. El caso habitual de uso de abstracts, es
    cómodo cuando no se asume nada del input.


- When specifying an interaction between two types from abstracts to more
concrete types, multiple dispatch will choose the most specific one. So, it is
important not only that the compiler checks that the type implements the
abstract contract, but it also has to check that no other function with the
same name and compatible input types breaks the contract.

This is one of the areas where it is worth preferring simpler rules over more
expressive ones. If the interaction between abstracts, generics and multiple
dispatch becomes difficult to explain, the design should be narrowed.


## Expresiveness

Abstract types in Julia are extremely flexible and powerful while being easy to
use. To have those simultaneously, they are just nominal. Thus, the languaje
doesn't know about what functions you can call with the abstract types. You
just call, and wait for the error at runtime.

If we want to have the same flexibility and power but with compile-time checking, we
need to have a way to express the possible interoperability between abstract types.


Challlenge for expresssiveness 1: "Abstract Matrices that interoperate".

```
AbstractMatrix#(.t: Type) : Abstract = (

    -- Closed under addition
    operator + (.left: Self, .right: Self) -> (.result: Self)

    -- Closed under multiplication
    operator * (.left: Self, .right: Self) -> (.result: Self)

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self, .right: AnyOther#(.t: t)) -> (.result: SomeOther#(.t: t))
    -- If you don't want to implement it with all other AbstractMatrix types,
    -- you can provide a default implementation that uses conversion to DenseMatrix.
)
```

Challenge for expressiveness 2: "Abstract Matrices that check dimensions at
compile time".


```
AbstractMatrix#(
    .t             : Type
    .indexing_type : Type:UInt
    .rows          : indexing_type
    .cols          : indexing_type
) : Abstract = (

    -- Rows and cols
    n_rows(.m: Self) -> (.n: indexing_type)
    n_cols(.m: Self) -> (.n: indexing_type)


    -- Get item
    operator get[] (.m: &Self, .i: IndexingSpec) -> (.r: t)

    -- Set item
    operator set[] (.m: $&Self, .i: IndexingSpec, .v: t) -> ()


    -- Addable with other matrix types of the same shape
    operator + (
        .left  : Self
	.right : AnyOther#(.t: t, .rows = rows, .cols = cols)
    ) -> (
	.result: SomeOther#(.t: t, .rows = rows, .cols = cols)
    )

    -- Multiplicable with other compatible AbstractMatrix types:
    operator * #(
        .right_matrix_cols: indexing_type
    ) (
        .left  : Self
        .right : AnyOther#(.t: t, .rows = cols, .cols = right_matrix_cols)
    ) -> (
        .result: SomeOther#(.t: t, .rows = rows, .cols = right_matrix_cols)
    )
)
```

---

> [!TODO] Pensar si implementar orphan rule o permitir type piracy como julia.
>
> Conviene tomarse esto en serio pronto. Si se permite demasiada libertad aquí,
> el lenguaje puede ganar expresividad pero perder modularidad y predictibilidad.

> [!TODO] Subtyping con genéricos.
> ¿Vector<Int64> es usable donde se espera Vector<Number>?


> [!TODO] Where clauses en la cabecera de funciones y de los abstracts.
> Pensar si merece la pena.

> [!TODO]
> Se permite que el abstract aporte tipos asociados?
