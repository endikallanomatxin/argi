# Abstract types

- Permiten definir qué funciones deben poder llamarse sobre un tipo.

- Obligan a especificar explícitamente qué tipos subyacen al abstract type.

- Permiten definir un tipo por defecto, que será el que se inicialice si se usa
  como tipo al ser declarado.

- NO permiten definir propiedades (Para evitar malas prácticas)

- Se pueden componer.

- Se pueden extender fuera de sus módulos de origen.


## Declaración

En el cuerpo del abstract, se pueden usar Self como el tipo que lo implementa.


Así se declara un abstract:

```
Animal : Abstract = (
	-- Las funciones se definen con la sintaxis de currying.
	speak(Self) := String
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


## PROBLEMAS

No son tan intercambiables.

> [!CHECK] Las dinámicas requieren alocar memoria extra, por lo que tendrán que tomar un allocator.


> [!CHECK] Vtables with multiple dispatch and abstract types?
> 
> ```
> bar : Abstract = (
>     foo(Self, Int) -> Int
>     baz(Self, Allocator) -> ()
> )
> ```
> 
> Como sabe el compilador qué función meter a la vtable, si no ha resuelto el
> dispatch de foo (Int) y baz (Allocator)?
> 
> Prohibir multiple dispatch en los abstracts resolvería el problema?


### Solución 1: Todo Vtable

Se puede hacer que todo lo genérico use vtables, como go.

Pero:

- pierdes performance
- alocar memoria lo hace incómodo.

NO


### Solución 2: No permitir abstracts en definiciones de funciones

- Estático, monomorfización, cero overhead, usando generics:

    ```
    sum_area#(.t: Shape) (.xs: []t) -> (.r: Float) := { … }
    ```

- Dinámico, virtual:

    ```
    sum_area (.xs: []Virtual#(Shape)) -> (.r: Float) := { … }
    ```

    Virtual types: Es para usar Vtable

    ```
    Virtual#(Foo) : Type = (
        .data_ptr: *anyopaque      // o inline storage si SBO
        .vtable:   *const Foo.Vtbl // tabla de fn ptrs derivada del Abstract
        .meta:     Meta            // type_id, flags de ownership, storage, etc.
    )
    ```

    Requiere un allocator.


Esto parece lo más limpio porque así evitamos que se complique por culpa del multiple dispatch.

Solo queda:

- aclarar como se hace vtables con multiple dispatch.
- pensar en una forma cómoda de no tener que poner todo el rato #(...) para los generics.


### Solution 3:

“Abstract siempre monomorfiza; si quieres despacho dinámico lo pides
explícitamente”

(Es similiar a la 2, pero más automático)



### Solution 4: Abstracts are only nominal, like in Julia

En julia los abstracts son solo etiquetas nominales, no tienen funciones que
tengan que implementar los tipos que los usan.

En las funciones, tu sistema se fía, pero luego te dirá al compilar que si no
se encuentra la función que llamar da error.

Eso podría simplificar las cosas.

Podríamos tener NominalAbstracts y BehavioralAbstracts.


En Julia, los abstract type no expresan contratos relacionales entre dos tipos
distintos (ni “si A y B se pueden multiplicar” ni “qué tipo resulta”).

La compatibilidad de pares (p. ej. OneHot × Dense, Diagonal × Sparse, Adjoint ×
Strided) no se declara en el abstract; se implementa como métodos de * para
combinaciones concretas (múltiple dispatch).

Como declarar algo más débil (“cada una se multiplica consigo misma”) no te
garantiza que A×B exista: solo asegura A×A y B×B; Julia pasa de eso.

Si mi lenguaje hace abstracts considerando sus funciones, obliga a que haya una
forma de expresar que para formarparte de ese abstract tiene que poder operarse
con todos los demás tipos que lo implementan. Si no, no hay forma de que sea
generico y a la vez se compruebe su funcionalidad.


---

Exploración de definir relaciones cruzadas en abstracts:

```
AbstractMatrix : Abstract = (

    -- Closed under multiplication
    operator * (.left: Self, .right: Self) -> (.result: Self)

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self, .right: AnyOther) -> (.result: AnyOther)
    -- If you don't want to implement it with all other AbstractMatrix types,
    -- you can provide a default implementation that uses conversion to DenseMatrix.
)
```

Será esto demasiado complejo y resultará en demasiado type masturbation?

Igual lo mejor es separar:

- Nominal abstracts (solo etiquetas, estilo julia). Para matrices, tipos matemáticos...
- Behavioral abstracts (con funciones).

El problema es que ya habíamos hecho todo el planteamiento del lenguaje
asumiendo que siempre ibamos a poder trazar los tipos de forma limpia gracias a
la información del tipe system.


Vamos a llevar el ejemplo un poco más alla:

```
AbstractMatrix#(t: Type) : Abstract = (

    -- Closed under addition
    operator + (.left: Self, .right: Self) -> (.result: Self)

    -- Closed under multiplication
    operator * (.left: Self, .right: Self) -> (.result: Self)

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self, .right: Other(t)) -> (.result: Other(t))
    -- If you don't want to implement it with all other AbstractMatrix types,
    -- you can provide a default implementation that uses conversion to DenseMatrix.
)
```


Rows and cols?

```
AbstractMatrix#(.t: Type, .rows: Int, .cols: Int) : Abstract = (

    -- Rows and cols
    n_rows(.m: Self) -> (.n: Int)
    n_cols(.m: Self) -> (.n: Int)


    -- Get item
    operator get[] (.m: Self, .i: IndexingSpec) -> (.r: t)

    -- Set item
    operator set[] (.m: Self, .i: IndexingSpec) -> (.r: t)


    -- Closed under addition
    operator + (.left: Self, .right: Self) -> (.result: Self)

    -- Sumar con otros tipos de matrices? Si no no puedo sumar dos
    -- AbstractMatrix cualquiera en el cuerpo de una función.

    -- Closed under multiplication
    operator * (.left: Self, .right: Self) -> (.result: Self)

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self, .right: AnyOther ) -> ( .result: SomeOther)
    operator * (.left: AnyOther, .right: Self ) -> ( .result: SomeOther)
)
```

Igual los generic parameters deberían poder checkear las dimensiones en la multiplicación?
Como podríamos plasmar eso? Igual es secundario y no necesario, lo único importante es que si al final opto por checkeo de tipos más allá que Julia, tengo que conseguir que se le puedan aplicar funciones a los tipos de datos que le entran a la función. El checkeo de dimensiones igual es algo secundario.



Exploración de checkeo de dimensiones para la multiplicación:

```
AbstractMatrix#(.t: Type, .rows: Int, .cols: Int) : Abstract = (

    -- Rows and cols
    n_rows(.m: Self) -> (.n: Int)
    n_cols(.m: Self) -> (.n: Int)


    -- Get item
    operator get[] (.m: Self, .i: IndexingSpec) -> (.r: t)

    -- Set item
    operator set[] (.m: Self, .i: IndexingSpec) -> (.r: t)


    -- Closed under addition
    operator + (.left: Self#(t,m,n), .right: Self#t,m,n)) -> (.result: Self#(t,m,n))

    -- Addable with other matrix types of the same shape
    operator + (.left: Self#(t,m,n), .right: AnyOther#(t,m,n)) -> (.result: SomeOther#(t,m,n))
    operator + (.left: AnyOther#(t,m,n), .right: Self#(t,m,n)) -> (.result: SomeOther#(t,m,n))

    -- Closed under multiplication
    operator * (.left: Self#(t,m,n), .right: Self#(t,n,p)) -> (.result: Self#(t,m,p))

    -- Multiplicable with other AbstractMatrix types:
    operator * (.left: Self#(t,m,n), .right: AnyOther#(t,n,p)) -> (.result: SomeOther#(t,m,p))
    operator * (.left: AnyOther#(t,m,n), .right: Self#(t,n,p)) -> (.result: SomeOther#(t,m,p))
)
```

Se puede simplificar (creo, veririficar):

```
AbstractMatrix#(.t: Type, .rows: Int, .cols: Int) : Abstract = (

    -- Rows and cols
    n_rows(.m: Self) -> (.n: Int)
    n_cols(.m: Self) -> (.n: Int)


    -- Get item
    operator get[] (.m: Self, .i: IndexingSpec) -> (.r: t)

    -- Set item
    operator set[] (.m: Self, .i: IndexingSpec) -> (.r: t)


    -- Addable with other matrix types of the same shape
    operator + (.left: Self#(t,m,n), .right: AnyOther#(t,m,n)) -> (.result: SomeOther#(t,m,n))

    -- Multiplicable with other compatible AbstractMatrix types:
    operator * (.left: Self#(t,m,n), .right: AnyOther#(t,n,p)) -> (.result: SomeOther#(t,m,p))
)
```

Mejor, con generics para las dimensiones:

```
AbstractMatrix#(.t: Type, .rows: Int, .cols: Int) : Abstract = (

    -- Rows and cols
    n_rows(.m: Self) -> (.n: Int)
    n_cols(.m: Self) -> (.n: Int)


    -- Get item
    operator get[] (.m: Self, .i: IndexingSpec) -> (.r: t)

    -- Set item
    operator set[] (.m: Self, .i: IndexingSpec) -> (.r: t)


    -- Addable with other matrix types of the same shape
    operator + #(
        .t    : Type
        .rows : Int
        .cols : Int
    ) (
        .left  : Self    #(t, rows, cols)
	.right : AnyOther#(t, rows, cols)
    ) -> (
	.result: SomeOther#(t, rows, cols)
    )

    -- Multiplicable with other compatible AbstractMatrix types:
    operator * #(
        .t           : Type
        .result_rows : Int
        .result_cols : Int
        .equal_dim   : Int
    ) (
        .left  : Self    #(t, result_rows, equal_dimension)
        .right : AnyOther#(t, equal_dimension, result_cols)
    ) -> (
        .result: SomeOther#(t, result_rows, result_cols)
    )

    -- Como mapeo los parámetros de self a esas funciones, que tienen una descripción más clara?
)
```

> [!CHECK] Como se habla eso con el dispatch?
> Si tengo dos funciones con mismo nombre pero distintas configuraciones de generics, se puede?
> Igual si hacemos que solo dependa de la firma, sí?
> Si los generics influyen en la firma... se lía?

> [!CHECK] Asegurar que no existen funciones que tomando ese nombre+input llevan a outputs que no cumplen el contrato.
> Si dices que un tipo cumple un abstract y luego das funciones para tipos
> específicos para operaciones más eficientes bien, sigue cumpliendo. Pero lo
> que puede ser peligroso es que con un input que cumpla el input del abstract
> te de un output que no cuadre con el output del abstract. Porque entonecs se
> le dará prioridad al resolver el dispatch y la liará, sacando los tipos del
> flujo esperado.

Posible volantazo: representar Abstracts relacionando tipos, no individualmente.
Pasar de "para ser una AbstractMatrix tiene que poder multiplicarse si sigue estas normas definidas en su Abstract" a "para poder multiplicar AbstractMatrix, tienen que cumplir esta abstract conjunta".

Al final el objetivo es que dentro de una función puedas hacer a+b o a*b y que el compilador sepa al menos qué cumple el resultado, para que no se convierta en un any, sino al menos en un AbstractMatrix.
Aunque claro... que eso se pueda cumplir es "lo mismo" que que un AbstractMatrix se pueda instaciar, lo que va un poco en contra de su definición.

Si el checkeo de dimensiones ocurre en el Abstract es como hasta ahora, para usarlo:

```
some_function(
    .a: AbstractMatrix#(t, m, n),
    .b: AbstractMatrix#(t, n, p)
) -> (.r: AbstractMatrix#(t, m, p)) := {
    r = a * b
}
```

Ahí tú puedes aplicar a*b porque existen las implementaciones para esas relaciones de dimensiones concretas.


Si el checkeo de dimensiones ocurre en el Abstracts adicicionales:

```
Multiplicable#(
    .a: AbstractMatrix#(t, m, n),
    .b: AbstractMatrix#(t, n, p),
    .r: AbstractMatrix#(t, m, p)
) : Abstract = (
    operator * (.left: a, .right: b) -> (.result: r)
)

some_function(
    .a: AbstractMatrix,
    .b: AbstractMatrix
) -> (.r: AbstractMatrix) where (
    Multiplicable#(a, b, r)
) := {...}

```

Pff no se yo, parece demasiado complejo, requiere mucho jaleo y complejidad. Si se puede prefiero lo anterior.

