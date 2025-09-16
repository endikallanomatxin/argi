# Abstract types

- Permiten definir qué funciones deben poder llamarse sobre un tipo.

- Obligan a especificar explícitamente qué tipos subyacen al abstract type.

- Permiten definir un tipo por defecto, que será el que se inicialice si se usa
  como tipo al ser declarado.

- NO permiten definir propiedades (Para evitar malas prácticas)

- Se pueden componer.

- Se pueden extender fuera de sus módulos de origen.

- Si se usan en la firma de una función, se monomorfiza por defecto, para usar
despacho dinámico en runtime, hay que usar Virtual#(AbstractType).

- Los subtipes de un abstract tienen que tener al menos los mismo compiletime
parameters que el abstract.


## Declaración

En el cuerpo del abstract, se pueden usar Self como el tipo que lo implementa.


Así se declara un abstract:

```
Animal : Abstract = (
	-- Las funciones se definen con la sintaxis de currying.
	speak (Self) -> String
)

speak (.d: Dog) -> (.s: String) := {
	return "Woof"
}

-- Requiere manifestación explícita de la implementación.
Animal canbe Dog

-- Permite definir un valor por defecto.
Animal defaultsto Dog
```

```
Addable : Abstract = (
	operator + (Self, Self) -> (Self)
)
```

To use with generics:

```
List#(t: Type) : Abstract = (
	operator get[](&Self, Int) -> (t)
	operator set[](!&Self, Int, t) -> ()
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
    -- You can mix functions and other Abstract here.
)
```

Cases:

- When a function takes more than one abstract type, types are not assumed to
be the same, to express that, use compile-time-parameters.

    ```
    foo#(.t: Type:ExampleAbstract) (.a: t, .b: t) -> (.r: t) := { ... }
    ```

    Todas las llamadas a funciones que usan abstracts se podrían expresar
    usando generics en realidad. El caso habitual de uso de abstracts, es
    cómodo cuando no se asume nada del input.


- When specifying an interaction between two types from abstracts to more
concrete types, multiple dispatch will choose the most specific one. So, it is
important not only that the compiler checks that the type implements the
abstract contract, but it also has to check that no other function with the
same name and compatible input types breaks the contract.


## Expresiveness

Abstract types in Julia are extremely flexible and powerful while being easy to
use. To have those simultaneously, they are just nominal. Thus, the languaje
doesn't know about what functions you can call with the abstract types. You
just call, and wait for the error at runtime.

If we want to have the same flexibility and power but with compile-time checking, we
need to have a way to express the possible interoperability between abstract types.


Challlenge for expresssiveness 1: "Abstract Matrices that interoperate".

```
AbstractMatrix#(t: Type) : Abstract = (

    -- Closed under addition
    operator + (.left: Self, .right: Self) -> (.result: Self)

    -- Closed under multiplication
    operator * (.left: Self, .right: Self) -> (.result: Self)

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self, .right: AnyOther(t)) -> (.result: SomeOther(t))
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
    operator get[] (.m: Self, .i: IndexingSpec) -> (.r: t)

    -- Set item
    operator set[] (.m: Self, .i: IndexingSpec, .v: t) -> ()


    -- Addable with other matrix types of the same shape
    operator + (
        .left  : Self     #(t, rows, cols)
	.right : AnyOther #(t, rows, cols)
    ) -> (
	.result: SomeOther#(t, rows, cols)
    )

    -- Multiplicable with other compatible AbstractMatrix types:
    operator * #(
        .right_matrix_cols: indexing_type
    ) (
        .left  : Self     #(t, rows, cols)
        .right : AnyOther #(t, cols, right_matrix_cols)
    ) -> (
        .result: SomeOther#(t, rows, right_matrix_cols)
    )
)
```

