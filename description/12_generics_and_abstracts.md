#### Polymorfism. Abstract.

> [!TODO] Decidir nombre
> Estoy entre: `abstract`, `interface`, `protocol`, `trait`

Los abstract types:
- Permiten definir qué funciones deben poder llamarse sobre un tipo.
- Obligan a especificar explícitamente qué tipos implementan el abstract.
- Permiten definir un tipo por defecto, que será el que se inicialice si se usa como tipo al ser declarado.
- NO permiten definir propiedades (Para evitar malas prácticas)
- Se pueden componer.
- Se pueden definir extender fuera de sus módulos de origen.


Así se declara un tipo abstracto:

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
Addable : Abstract = (
	operator +(_, _) : _
)
```

To use with generics:

```
List#(t: Type) : Abstract = (
	operator get()(_, _) := t
	operator set()(_, _, t)
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
	-- You can mix functions and other abstract types here.
)
```


> [!CHECK]
> Si defines una función que toma un par de abstracts, ints por ejemplo, tienen
> que ser el mismo tipo? Como se desambigua eso?


