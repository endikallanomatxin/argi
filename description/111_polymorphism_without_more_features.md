## Polymorphism without adding features

### Using generics for static polymorphism

Homogeneous list operation example:

```
-- Pensar una forma más elegante de checkear esto:
is_addable(.t: Type) -> Bool := #compiles({ var a:T; var b:T; _ = a.add(b) })
has_zero(.t: Type) -> Bool := #compiles({ var a:T; _ = a.zero })

sum#(.t: Type) #where is_addable(t) and has_zero(t)
(.xs: List#(t)) -> (.out: t) := {
    ...
}
```


### Using vtables for dynamic polymorphism

Heterogeneous list operation example:

```
AnyAddable : Type = (
    .data      : &Any
    .functions : (
        .add: (a: &Any, b: &Any) -> &Any
    )
)
```

`AnyAddable` already can be a type in the generic function defined before.

To create that list:

```
my_list : List#(Any) = (1, 2.3, 4i)

my_list | into_any_addable(_) | sum (_)
```


### Críticas

Es complicado de aprender para los nuevos, requiere entender todo antes de poder usarlo.


## Iterators

### Con vtable

```
Iterator : Type = (
    .next     : &Function
    .has_next : &Function
)
```

Pero entonces tendrían que ser closures.


### Usando multiple dispatch

```
next (.mtit: MyTypeIterator) -> (.out: MyType) := {
	-- Do something with mtit
}

has_next (.mtit: MyTypeIterator) -> Bool := {
	-- Do something with mtit
}
```

Pero como hacemos para que el compilador tome MyTypeIterator como un iterador? Si usamos un Any, es una mierda. Y si hacemo que lo compruebe, realmente estamos implementando traits no?


### Using traits for polymorphism

```
Itetator#(.t: Type) : Trait = (
    has_next: (_) -> Bool
    next: (_) -> t
)

my_collection | iterator(&_) | sum (_)

-- o

for element in my_collection|iterator(&_) {
    -- Do something with element
}
```

Es que es lo que mejor queda, encima, como conoce el tipo en compile time, se puede monomorfizar y optimizar.
Es que traits muy bien.

