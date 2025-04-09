# Funciones

Functions are first class citizen.

## Function definition syntax

```
add(a: Int, b: Int) := Int {
	return a+b
}
```

return variables are initialized (to zero) if named.

```
calculate_stats(list: List) := (mean: Float, standard_deviation: Float) {
	for element in list
		...
	return (mean, standard_deviation)
}
```

Most extended syntax to add documentation

```
my_function
	---
	Explanation of what the function does
	---
(
	a: int  -- Short description of a
	b: bool
	---
	Longer description of b
	---
	verbose: bool = False  -- Default value
) := (
	result_one: bool
	result_two: int
){
	...
	return x
}
```


#### Argument passing: By value and deep copied

**Everything is passed by value** (as in C, zig, odin...)

Es problema con pasar por valor, es que los tipos que contienen memoria alojada en el heap (por ejemplo un map de zig) se van a copiar los estructs que los modelizan con sus punteros, pero no se va a duplicar la memoria referenciada por sus punteros.

```
m1 = Map|init()
m2 = m1
m2.put("key", "value") -- Cambia el original

m1.deinit()
m2.deinit() -- Double free error
```

Esto:
- es bastante lío sobre todo para los nuevos.
- obliga a conocer la implementación para poder usar el tipo adecuadamente. (por ejemplo tienes que sabe si es un struct con punteros a memoria)

Para solucionar esto: Haremos deep_copy por defecto (donde deep_copy es un método que tiene que estar definido para el tipo de variable en cuestión).

```
m1 = Map|init()
m2 = m1  -- Aquí se hace m2 = m1|deep_copy
```

Así todo se comporta como lo que se espera de primitivos.

Algunos tipos (archivos, sockets, dispositivos de hardware, semáfores, GPU buffers...) no tiene sentido definir una deep copy. En estos casos, directamente no se puede pasar por valor, solo con un puntero. Así eres extra-explícito.

Gracias a que la copia requiera una implementación explícita, da la oportunidad de gestionarlo adecuadamente.

Uso:

- Si no pones nada. Se llama al método deep_copy() para obtener la variable de entrada.
- Si pones ~ se hace una shallow copy y se pasa eso.
- Si pasas un puntero &, te permite leer.
- Si pasas un puntero &!, te permite leer y escribir.

```
var   -- deep copy
~var  -- shallow copy (valorarlo)
&var  -- inmutable pointer
$&var -- mutable pointer (s is for "side effect")
```

La sintaxis básica para pasar punteros 

```
funcion_que_recibe_puntero(p_datos: &Map<String,Int>) := {
	-- Aquí se usa: p_datos
	-- Es un puntero
	...
}

funcion_que_recibe_puntero(&datos)
```

Para hacer la de-referencia automática, se hace así:

```
funcion_que_lee(&datos: Map<String,Int>) := {
	-- Aquí se usa: datos
	-- Es un map
	...
}

funcion_que_lee(&datos)
```

Pero no deja mutar lo que hay al otro lado del puntero. Si se quiere mutar el valor hay que pasar con un indicador de que es una referencia mutable:

```
funcion_que_escribe($&datos: Map<String,Int>) := {
	-- Aquí se usa: datos
	-- Es un map
	...
}

funcion_que_escribe($&datos)
```

Hacer esto bien hace que no haga falta decir si las funciones son puras o tienen side effects.



#### Side effects

If a function has side effects, it requires marking with `$`, and it propagates.

This allows to understand the effect of a function at a glance, avoiding unexpected side effects. This is in some way a capability-based programming style.

It encourages the use of pure functions, which are easier to reason about and test; and dependency injection, which allows for more explicit, flexible and modular code.

For example, accessing a database:

```rg
import db

main! := {
	-- Creamos una conexión a la base de datos
	db_conn = db.open_database("my_db")

	-- Llamada a una función pura que consulta la base de datos
	user = query_user($&db_conn, 123)
}

query_user($&db_conn: $&DbConnection, user_id: Int) := User? {
	-- Acceso a la db
	row = db_conn|execute(!&_, "SELECT * FROM user WHERE id = ?", user_id)
	if row == null {
		return null
	}
	user = parse_user(row)
	return user
}
```

##### Closures

Cuando una función accede a variables de un scope exterior, tiene que indicarlo con un `!`.

```
variable := 4

contador$ := {
	variable++
}

contador$()  -- variable = 5
```

Así queda claro (y con una sintaxis similar a la de los argumentos) si una función tiene side effects.

Cuando se acceden constantes o definiciones de funciones exteriores, no hace falta indicarlo, es solo para variables. Así no es problema usar librerías, por ejemplo.

_(En realidad, me gustaría prohibir las closures (me parecen un poco antipattern). Pero bueno, con identificarlas claramente igual vale.)_


>[!TODO] Si dentro capturas por referencia de solo lectura? Eso habría que indicarlo?
> No, porque no es un side effect. Pero si lo haces, lo haces con un `&`.


##### The case for printing

Printing to the terminal is writing to a file, so it is a side effect, and should be marked as such.

So, as with the database, we can do dependency injecion, and use a file handle to print to the terminal or to a file.

```rg
import io
import fs


main$ := {
	-- Creamos un archivo de IO
	stdo = io.std.get_stdo()

	-- Llamada a una función pura que imprime
	do_something_pure(123, log = $&stdo)
}

-- Podemos usar el hecho de que tome stdo para controlar si queremos que imprima
do_something_pure(a: Int, $&log: Buffer? = null) := {
	if log { log|write($&_, "Hello, world\n") }
}
```

Una cosa buena es que hace fácil hacer todo el log a un archivo de logueo. Y deja claro donde ocurre el printing.

However, this can be quite tedious, and it is not always necessary to have this level of control over the output, specially when debugging.

If we just did something like:

```rg
print$("Hello, world")
```

That would be a side effect, and would require the side effect to be marked. And it would be propagated to the functions that call it. That would make the mark unhelpful.

For that, we have a special keyword for ignoring side effects:

```rg
ignore print$("Hello, world")
```
(también podría ser disregard o dismiss)



El compilador podría decirte al hacer audit, si ve que hay muchas funciones con side effects, entonces te avisa de que hay un problema de diseño. Y que le eches un ojo a lo que es la dependency injection.

(Hacer el printf debuggin un poco más complicado en realidad hará que la gente use más asserts. Pero el assert, a donde imprime?)

> Assert debería ser una función pura? Yo creo que sí, porque tras modificar el estado crashea.



### Dispatch

Multiple dispatch como Julia.

Pero hay que ehacer monomorfización de las funciones en tiempo de compilación.

Te permite funcionamiento similar al del static dispatch por objetos, pero de una forma más flexible.

Da error cuando hay ambigüedad en especificidad, pero se encarga el compilador de evitarlo.

En go, no se puede definir métodos de struct de otros paquetes. Eso es una mierda!


### Operator overloading

```
operator + (&v1: Vector, &v2: Vector) := Vector {
    return Vector(v1.x + v2.x, v1.y + v2.y)
}
```


### Currying

El currying puede quedar superlimpio en algunas ocasiones.

Por ejemplo en go, http.HandleFunc("patron", funcion) requiere que la función tenga como argumentos (r, w) y eso impide que puedas ponerle argumentos como tu base de datos o plantillas (lo que es necesario para hacerlo con funciones puras y no a través de globales.)

Una buena forma sería una sintaxis cómoda de hacer currying.

```
mux|HandleFunc("pattern", my_function(_a, _b, database, templates))
```


### Pipe operator

Llama a la función de la derecha con los argumentos devueltos por la función de la izquierda.
A veces hay que usar currying para cuadrar argumentos.

```
my_var|my_func
my_var|my_func(_, other_arg)
my_var|my_func(_1, other_arg, _2)  -- Multiple piped arguments
```

Si se pasa por referencia:

```
my_var|my_func(&_)
my_var|my_func(&_, second_arg)
```

