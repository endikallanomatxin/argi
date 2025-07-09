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


## Loops

For

```plaintext
for element in list {
    ...
}

for element, index in list|enumerate {
	...
}

for i in 1..10 {
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
(i*2 for i in 1.10)
```

O igual del revés:
- Se lee antes que se trata de un list comprehension.
- Queda más limpio para multiples líneas,

```
evens = (for i in 1..10 {yield i*2})

evens = (for i in 1..10; i*2)
```

>[!TODO] Darle una vuelta a la sintaxis.

### Iterators

Los `Iterator` gestionan como se recorren o procesan las colecciones, pero definiendose en un tipo nuevo para mantener independencia con los propios datos.

Se puede hacer a través de abstrascts:

```
Iterable : Abstract = (
    cast _ -> Iterator<_>
)

Iterator<T> : Abstract = (
    next _ -> T
    has_next _ -> Bool
)
```

> [!CHECK]
> Aquí como deberíamos gestionar abstract con generics?


En rust hay tres tipos: iter (inmutable), iter_mut (mutable), into_iter(pasando ownership)

Igual puede hacerse con multiple dispatch:

```
| to(Iterator)
| to(MutableIterator)
```

Y así se consigue el comportamiento deseado para distintos casos.


Se puede hacer igual también que las funciones map(), filter() y demás tengan versiones que consumen iteradores (para lazy evaluation) o listas.
_(Pensar en una forma de que esto sirva para vectorizar funciones. Que si la función llamada tiene una versión vector la tome, si no elemento a elemento)_


Y para hacer que tu tipo pueda ser iterable:

```
MyType : Type = struct (
    .data: List<Int>
)

cast MyType -> MyTypeIterator := {
    return MyTypeIterator (.data = in.data, .index = 0)
}

MyTypeIterator : Type = struct (
    .data: &MyType
    .index: Int
)

next MyTypeIterator -> Int := {
    if in.index >= in.data|len {
        throw "No more elements"
    }
    in.index += 1
    out = in.data(in.index-1)
}

has_next MyTypeIterator -> Bool := {
    return in.index < in.data|len
}
```


```
for element in my_collection {
    print(element)
}

-- Se podría escribir como:

iter : Iterator = my_collection | cast  -- Se puede castear a un abstract?
while iter|has_next {
    element = iter|next
    print(element)
}
```

DUDA: EL bucle for traga un iterable o un iterador?

Ideas:
- Concatenar iteradores con comas: `1..5, 80..92`
- En julia: The dot after sin causes the trigonometric function to be “broadcast” to each element of x.


