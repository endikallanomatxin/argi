## Conditionals

#### If

```
if a == 2 {
	...
} else if a == 3 {
	...
} else {
	...
}
```

#### Match

De odin: cada case es su propio scope, `implicit break` por defecto, y si en lugar de eso quieres que siga le pones un `fallthrough` o algo así.

```
match x (

	a {
		...
	}

	b {
		...
	}

	...
)
```

> [!NOTE]
> Aquí, como hemos quitado () para representar las funciones, podríamos usarlas para mejorar la sintaxis si fuera necesario.

Rust creo que hace esto muy bien.
Gleam también.

> [!CHECK]
>
> En JAI un switch se hace como algo así:
> 
> ```
> if bar == {
>     case 1 {
> 		...
> 	}
>     case 2 {
> 		...
> 	}
>     case 3 {
> 		...
> 	}
> }
> ```
> 
> Eso es como multiplexar una == y me parece muy buena idea, es más potente todavía que un match.
> 
> Darle una vuelta.

Los bindings de patrón en `match` deben seguir el mismo modelo general de
access modes:

```rg
match value {
    ..some payload {
    }

    ..some & payload {
    }

    ..some $& payload {
    }

    ..some ~ payload {
    }

    ..some _ {
    }
}
```

Regla unificada:

- `name` bindea por valor
- `& name` bindea una referencia read-only
- `$& name` bindea una referencia mutable
- `~ name` bindea por move
- `_` ignora el valor


## Loops

For

```plaintext
for element in list {
    ...
}

for element, index in list|enumerate {
	...
}

for i in Range(.start = 1, .end = 10) {
    ...
}
```

While

```plaintext
while eps < e-5 {
    ...
}
```

Para siempre:

```plaintext
loop
    ...
```


### List comprehensions

No me gustan, pero son muy cómodos para cosas pequeñas y no creo que tengan mucho riesgo de usarse mal en exceso. No pasa nada por implementarlos.

```
(i*2 for i in Range(.start = 1, .end = 10))
```

O igual del revés:
- Se lee antes que se trata de un list comprehension.
- Queda más limpio para multiples líneas,

```
evens = (for i in Range(.start = 1, .end = 10) {yield i*2})

evens = (for i in Range(.start = 1, .end = 10); i*2)
```

>[!TODO] Darle una vuelta a la sintaxis.

### Iterators

Los `Iterator` gestionan cómo se recorren o procesan las colecciones, pero se
definen en un tipo nuevo para mantener independencia respecto a los propios
datos.

`for` debe consumir un `Iterable`, no un `Iterator` directamente. El iterable
expone `to_iterator`, y el iterador mantiene el estado mutable del recorrido.

Se puede hacer a través de `Abstract`:

```
Iterable#(.t: Type) : Abstract = (
    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)

ROPointerIterable#(.t: Type) : Abstract = (
    to_ro_pointer_iterator(.value: &Self) -> (.iterator: Iterator#(.t: &t))
)

RWPointerIterable#(.t: Type) : Abstract = (
    to_rw_pointer_iterator(.value: $&Self) -> (.iterator: Iterator#(.t: $&t))
)

Iterator#(.t: Type) : Abstract = (
    has_next(.self: &Self) -> (.ok: Bool)
    next(.self: $&Self) -> (.value: t)
)
```

La decisión de diseño es mantener un único abstract `Iterator`. Lo que cambia
según el modo de iteración no es la interfaz del iterador, sino el abstract
`Iterable` que la colección decide implementar.

Eso deja el modelo así:

- `Iterable#(.t: T)` para `for item in value`
- `ROPointerIterable#(.t: T)` para `for & item in value`
- `RWPointerIterable#(.t: T)` para `for $& item in value`

Cada uno construye un `Iterator`, pero con distinto tipo de elemento:

- `Iterator#(.t: T)` para iteración por valor
- `Iterator#(.t: &T)` para iteración prestada read-only
- `Iterator#(.t: $&T)` para iteración prestada mutable

Nota conceptual útil: en Rust el `for` sigue siendo uno solo, pero el modo de
iteración lo decide el tipo de la expresión que se le pasa.

```
for x in v      -- consume la colección
for x in &v     -- itera por referencia inmutable
for x in &mut v -- itera por referencia mutable
```

Eso sale de distintas implementaciones de conversión a iterador para:

- `Vec<T>`
- `&Vec<T>`
- `&mut Vec<T>`

La idea interesante para Argi es conservar el mismo principio: `for` consume un
`Iterable`, y el tipo exacto del valor que se le pase debería poder determinar
si la iteración es por valor, por referencia inmutable o por referencia
mutable.

Dirección futura dentro del mismo marco:

```rg
for item in arr {
}

for & item in arr {
}

for $& item in arr {
}

for ~ item in arr {
}
```

Eso debe comportarse como el análogo en `for` de `place`, `&place`, `$&place`
y `~place`.

Para `0.1`, el recorte implementado se centra en:

- `for item in value`
- `for & item in value`
- `for $& item in value`

La iteración por transferencia:

```rg
for ~ item in value {
}
```

se deja explícitamente para `0.2`, porque necesita cerrar mejor la semántica de
consumo de colecciones e iteradores.

Se puede hacer igual también que las funciones map(), filter() y demás tengan versiones que consumen iteradores (para lazy evaluation) o listas.
_(Pensar en una forma de que esto sirva para vectorizar funciones. Que si la función llamada tiene una versión vector la tome, si no elemento a elemento)_


Y para hacer que tu tipo pueda ser iterable:

```
MyType : Type = struct (
    .data: List#(.t: Int)
)

MyTypeIterator : Type = (
    .data: &MyType
    .index: UIntNative
)

MyType implements Iterable#(.t: Int)
MyType implements ROPointerIterable#(.t: Int)
MyTypeIterator implements Iterator#(.t: Int)
MyTypeROIterator implements Iterator#(.t: &Int)

to_iterator(.value: &MyType) -> (.iterator: MyTypeIterator) := {
    iterator = (
        .data = value,
        .index = 0,
    )
}

has_next(.self: &MyTypeIterator) -> (.ok: Bool) := {
    ok = self&.index < length(.value = self&.data&.data)
}

next(.self: $&MyTypeIterator) -> (.value: Int) := {
    current_index :: UIntNative = self&.index
    value = self&.data&.data[current_index]
    self& = (
        .data = self&.data,
        .index = current_index + 1,
    )
}

to_ro_pointer_iterator(.value: &MyType) -> (.iterator: MyTypeROIterator) := {
    iterator = (
        .data = value,
        .index = 0,
    )
}

next(.self: $&MyTypeROIterator) -> (.value: &Int) := {
    -- devolvería una referencia al elemento actual
}
```


```
for element in my_collection {
    print(element)
}

-- Se podría escribir como:

it ::= to_iterator(.value = &my_collection)
while has_next(.self = &it) {
    element := next(.self = $&it)
    print(element)
}
```

El `for` debe tragar un `Iterable` del modo adecuado:

- `for item in x` requiere `Iterable`
- `for & item in x` requiere `ROPointerIterable`
- `for $& item in x` requiere `RWPointerIterable`

Ideas:
- Concatenar iteradores con comas: `Range(.start = 1, .end = 5), Range(.start = 80, .end = 92)`
- En julia: The dot after sin causes the trigonometric function to be “broadcast” to each element of x.
