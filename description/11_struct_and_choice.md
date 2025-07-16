## Structs

This declares a new struct type:

```
Pokemon : Type = (
	.ID   : Int64  = 0    -- It allows default values
	.Name : String = ""
)
```


This declares a new anonymous struct:

```
data : (
	.ID   : Int64    -- Struct type literal
	.Name : String
) = (
	.ID = 0          -- Struct value literal
	.Name = ""
)
```

Structs' types are structural only when anonymous.


##### Protected fields

Es importante proteger algunos campos para conseguir una mejor encapsulación.

Los campos que empiecen por _ serán privados y no podrán ser accedidos desde fuera del package.

Por ejemplo:

```
MyStruct : Type = (
	._x :: Int = 0
)

get_x(s: MyStruct) := Int {
	return s._x
}

set_x(s: MyStruct, x: Int) {
	s._x = x
}
```

También puede ser útil para garantizar que un struct se inicializa correctamente.

```
MyStruct := (
	._x :: Int = 0
	._y :: Int = 0
	._z :: Int = 0
)

init (x: Int, y: Int, z: Int) -> MyStruct := {
	return MyStruct(x, y, z)
}
```

We use dynamic dispatch by return type to create the initializer.

```
my_var : MyType = (1, 2, 3)
```

Esto realmente es:

```
my_var : MyType = init (1, 2, 3)
```

y queda muy limpio.


> [!IDEA] Struct field types
> Cuando tienes una app web en go por ejemplo, tienes structs para tus models que tienen un montón de campos que más adelante no vas a usar siempre al completo.
> A veces aunque solo tengas que usar el campo del ID pasas el struct entero para al menos mantener la semántica.
> Igual se podría hacer que cuando se define un struct también se definen tipos nuevos.
> 
> Por ejemplo:
>
>	```
>	User := (
>		ID    :: Int64
>		Name  :: String
>	)
>	userIDs : List(User.ID)  -- En lugar de Users, o simplemente Int64
>	```
>
> Con esto ganamos la información semántica de a qué corresponde lo que estamos usando, sin pagar el precio de pasar todo el struct.


## Choice

```
Direction : Type = (
	=..north  -- Default
	..east
	..south
	..west
)

int(Directions..north) == 1
```

```
-- This suffices as a ChoiceLiteral for assignment
..north
```

```
HTTPCode : Type = (
	..OK = 200                   -- Specific underlying representation
	..NotFound = 404
	..InternalServerError = 500
	-- Si poners uno, tienes que poner todos.
)
```

```
-- With other data types besides Int

-- Strings
Role : Type = (
	..admin = "admin"
	..user = "user"
	..guest = "guest"
)

-- Floats
Multiplyier : Type = (
	..mili = 0.001
	..centi = 0.01
	..deci = 0.1
	..base = 1
	..deca = 10
	..hecto = 100
	..kilo = 1000
)
```

##### Payload

Like a tagged union.

```
Errable#(.t: Type, .e: Error) : Type = (
	..ok(t)
	..error(e)
)
```

```
Nullable#(.t: Type) : Type = (
	=..none
	..some(t)
)
```

##### Use

###### Checking for them

```
x|is(..north)  -- Check if x is north
```

###### Getting a payload

```
x..ok
```

En rust (a parte del match) se puede hacer así:

```
// Ejemplo con Option
let x: Option#(Int32) = Some(10);
if let Some(v) = x {
println!("Valor: {}", v);
}
```


###### Matching

```
match x {
	..north { println("North") }
	..south { println("South") }
	..east  { println("East") }
	..west  { println("West") }
}
```

With a payload

```
match x {
	..ok(v) { println("Value: ", v) }
	..error(e) { println("Error: ", e) }
}
```

> [!NOTE] Eso es muy rust
> No se si cuada mucho con nuestro lenguaje.
> Igual hay que darle una vuelta a una sintaxis más general, que aplique más alla de los choice with payload.



