# Choice

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



