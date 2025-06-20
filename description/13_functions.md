# Funciones

Functions are first class citizen.

All functions are unary.


## Function definition syntax

```
add ( .a: Int, .b: Int ) -> Int := {
    out = in.a + in.b          -- `in` y `out` son structs implícitos
}

square Int -> Int := {out = in^2}
```

- Todos los parámetros viajan en un único struct de entrada (in).
- Todos los resultados se devuelven en un único struct de salida (out).


return variables are initialized (to zero) if named.

```
calculate_stats List -> (.mean: Float, .standard_deviation: Float) := {
	for element in in{
		...
	}
	out := (mean, standard_deviation)
}
```

> [!CHECK]
> Los argumentos de salida, cuando se inicializan?
> Usan su init? O simplemente son el struct que los representa, sin campos.
> Igual esperan a su primera asignación para llamar a init.


Most extended syntax to add documentation

```
my_function
	---
	Explanation of what the function does
	---
(
	.a: int  -- Short description of a
	.b: bool
	---
	Longer description of b
	---
	.verbose: bool = False  -- Default value
) -> (
	.result_one: bool
	.result_two: int
) {
	...
}
```

The empty struct literal is like saying void:

```
my_function () -> () := {
	-- No recibe ni devuelve nada
}
```

> [!CHECK] Can you ommit things?


## Pipe operator

Llama a la función de la derecha con los argumentos devueltos por la función de
la izquierda. A veces hay que usar currying para cuadrar argumentos.

```
my_var | my_func
my_var | my_func (_, other_arg)
my_var | my_func (_.a, other_arg, _.b)  -- Multiple piped arguments
```

> [!IDEA]
> Si los output arguments son named, se pueden usar en lugar de los _1, _2...
> Pensar en como hacerlo para que no colisione con los nombres de las variables.

Si se pasa por referencia:

```
my_var | my_func &_
my_var | my_func (&_, second_arg)
```

Permite emular la comodidad de los objetos.

> [!FIX] Si la función que opera sobre un "objeto" proviene me un módulo,
> habría que mencionar el módulo. Es un poco tedioso.


## Argument passing: By value and deep copied

**Everything is passed by value** (as in C, zig, odin...)

Es problema con pasar por valor, es que los tipos que contienen memoria alojada
en el heap (por ejemplo un map de zig) se van a copiar los estructs que los
modelizan con sus punteros, pero no se va a duplicar la memoria referenciada
por sus punteros.

```
m1 : Map = ()
m2 := m1
m2 | put ($&_, "key", "value") -- Cambia el original

m1 | deinit $&_
m2 | deinit $&_ -- Double free error
```

Esto:
- es bastante lío sobre todo para los nuevos.
- obliga a conocer la implementación para poder usar el tipo adecuadamente.
(por ejemplo tienes que sabe si es un struct con punteros a memoria)

Para solucionar esto: Haremos deep_copy por defecto (donde deep_copy es un
método que tiene que estar definido para el tipo de variable en cuestión).

```
m1 : Map = ()
m2 = m1  -- Aquí se hace m2 = m1|deep_copy
```

Así todo se comporta como lo que se espera de primitivos.

Algunos tipos (archivos, sockets, dispositivos de hardware, semáfores, GPU
buffers...) no tiene sentido definir una deep copy. En estos casos,
directamente no se puede pasar por valor, solo con un puntero. Así eres
extra-explícito.

Gracias a que la copia requiera una implementación explícita, da la oportunidad
de gestionarlo adecuadamente.

Uso:

- Si no pones nada. Se llama al método deep_copy() para obtener la variable de
entrada.
- Si pones ~ se hace una shallow copy y se pasa eso.
- Si pasas un puntero &, te permite leer.
- Si pasas un puntero $&, te permite leer y escribir.

```
var   -- deep copy
&var  -- inmutable pointer
$&var -- mutable pointer (s is for "side effect")
```

La sintaxis básica para pasar punteros 

```
funcion_que_lee &Map<String,Int> -> () := {
	-- Usamos in& para desreferenciar al usarlo.
	...
}

funcion_que_lee &datos
```

Pero no deja mutar lo que hay al otro lado del puntero. Si se quiere mutar el
valor hay que pasar con un indicador de que es una referencia mutable:

```
funcion_que_escribe $&Map<String,Int> := {
	-- Usamos in& para desreferenciar al usarlo.
	-- Pudiendo modificar el valor al que apunta.
	...
}

funcion_que_escribe $&datos
```


#### Automatic dereferencing syntax

Es habitual que dentro de la función que recibe los punteros, realmente
querramos tratar el valor al que apunta el puntero como el propio valor.

Para eso, se puede usar la sintaxis de dereferencia automática:

```rg
funcion_que_lee &Map<String,Int>& := {
	...
}

funcion_que_escribe $&Map<String,Int>& := {
	...
}
```


Esto hace que dentro de la función se pueda usar directamente `datos` y que se
comporte como si hicieras `datos&`.

Siempre que solo se use el valor y no se haga nada con el puntero en sí, el
compilador te recomendará usar esta sintaxis. Así se garantiza que cuando se
pasa un puntero a las funciones de dentro, se vea el &datos y el $&datos, y
quede claro que estás pasando por referencia.

> [!TODO] Actualizar el resto del código a esta sintaxis


#### Side effects

If a function has side effects, it requires marking with `$`, and it
propagates.

This allows to understand the effect of a function at a glance, avoiding
unexpected side effects. This is in some way a capability-based programming
style.

It encourages the use of pure functions, which are easier to reason about and
test; and dependency injection, which allows for more explicit, flexible and
modular code.

For example, accessing a database:

```rg
import db

main system:$&System -> sc:StatusCode := {
	-- Creamos una conexión a la base de datos
	db_conn = db.open_database("my_db")

	-- Llamada a una función pura que consulta la base de datos
	user = query_user($&db_conn, 123)
}

query_user (.db_conn: $&DbConnection, .user_id: Int) -> ?User {
	-- Acceso a la db
	row = db_conn|execute($&_, "SELECT * FROM user WHERE id = ?", user_id)
	if row == null {
		return null
	}
	user = parse_user(row)
	return user
}
```

> [!NOTE] Igual hemos dado con una buena sintaxis para nombrar a los argumentos si queremos.
> Y si no ponemos nada, que sean in y out, para tener una sintaxis cómoda para lambdas rápidas.


##### Closures

Veo distintas formas de closures posibles:

- Uso de variables de un scope exterior.

	- Por valor, no problem. Se captura el dato en la función. No requiere
	indicación de side-effect.

	- Por referencia, probablemente lo mismo.

	- Por referencia mutable, REQUIERE INDICACIÓN DE SIDE EFFECT.

- Reasignación de variables de un scope exterior. REQUIERE INDICACIÓN DE SIDE
EFFECT.

```
variable := 4

contador$ () -> () := {
	variable += 1
}

contador$ () -- variable = 5
```

> [!CHECK] Es así como debe llamarse a una función sin argumentos de entrada?

Así queda claro (y con una sintaxis similar a la de los argumentos) si una
función tiene side effects.

> [!TODO] Pensar si realmente queremos permitir closures con side effects.
> Haskell, por ejemplo, no lo permite. Y en realidad me parece bastatante
> anti-pattern, igual es mejor prohibirlo. Así el lenguaje queda más limpio, y
> encima $ colorea las funciones.


##### Capabilities

Capabilities define what a function can do, and they have to be explicitly
passed to the function. All of them are passed to the main function, and can be
passed to other functions as needed.

```
main(system: $&System&) := {
	...
}
```

System is a struct that contains all the capabilities of the system.
(Inspired by Haskell's `IO` monad)

```
System : struct (
  terminal : $& Terminal,
  args     :  & Arguments,
  env_vars : $& EnvironmentVariables,
  file_sys : $& FileSystem,
  network  : $& Network,
  proc_man : $& ProcessManager,
  clock    : $& time.Clock,
  rand_gen : $& random.RandomNumberGenerator,
)

```

Examples of use:

```rg
main system:$&System& -> sc:StatusCode := {
	-- Acceso a la consola
	system.terminal | print ($&_, "Hello, world")

	-- Acceso a los argumentos de la línea de comandos
        argsmap := system.args | parse &_
        if argsmap has ($&_, "name") {
            greet_user (argsmap("name"), $&system.terminal.stdout)
        }

	-- Acceso a las variables de entorno
	env_var = system.env_vars | get (&_, "MY_ENV_VAR")

	-- Acceso al sistema de archivos
	file1 = system.file_sys | open_file_for_read (&_,"my_file.txt")
	content = file1 | read_all &_
	file2 = system.file_sys | open_file_for_write ($&_,"output.txt")
	file2 | write ($&_, content)

	-- Acceso a la red
	response = system.network | http_get (&_, "https://example.com")

	-- Acceso al proceso
	system.proc_man | run_command (&_, "ls -l")

	-- Acceso al reloj
	current_time = system.clock | now &_

	-- Generación de números aleatorios
	system.rand_gen | set_seed ($&_, 42)
	random_number = system.rand_gen | next_int ($&_, 1, 100)
}
```

Capabilities are implemented as abstract types. Sometimes they can be empty
structs, in which case they are ignored by the compiler when generating machine
code. No se si es mejor abstract o structs.

```rg
Clock : Abstract = (
    now         &_              -> TimeStamp
    sleep       (&_, Duration)  -> ()
    sleep_until (&_, TimeStamp) -> ()
)
```

```rg
Rng : Abstract = (
    next_bytes ($&_, Int)                -> Array<Byte>
    next_int   ($&_, min: Int, max: Int) -> Int
)
```


> [!IDEA]
> Podría haber nombres de resevados, que si los usas automáticamente se pone el
> input en todas las llamadas a funciones hasta llegar a main.
> file_sys, terminal, env_vars, args, network
> Así es cómodo meter un print por ejemplo.
> Si guardas y algunas de estas no usaste, se borra del input.


##### The case for printing


```rg
import io
import fs


main system:$&System& -> sc:StatusCode := {
	-- Creamos un archivo de IO
	stdo = system.terminal.stdout

	-- Llamada a una función pura que imprime
	do_something_pure(123, log = $&stdo)
}

-- Podemos usar el hecho de que tome stdo para controlar si queremos que imprima
do_something_pure(a: Int, $&log: Buffer? = null) := {
	if log { log|write($&_, "Hello, world\n") }
}
```



###### The case for halting the program

Halting is a capability.


### Dispatch

Multiple dispatch como Julia.

Pero hay que ehacer monomorfización de las funciones en tiempo de compilación.

Te permite funcionamiento similar al del static dispatch por objetos, pero de
una forma más flexible.

Da error cuando hay ambigüedad en especificidad, pero se encarga el compilador
de evitarlo.

En go, no se puede definir métodos de struct de otros paquetes. Eso es una
mierda!

#### Multiple dispatch for default implementations

Se puede usar para hacer implementaciones por defecto para cualquier struct por
ejemplo (consiguiendo funcionalidades como los derive macros de rust)

```rg
to(&s: Struct, t: type == String) := (string: String) {
	string = s.symbol_name + "("
	for field in s.fields
		string += field.name + ": " + field.value + ", "
	string += ")"
	return string
}
```

> [!IDEA]
> Para que algo sea hasheable todos sus campos tienen que ser hasheables. Si
> esa verificación en una comptime function se puede usar para el lsp.
> Igual se podría pensar como algo similar a una interface, pero que en lugar
> de checkear que cuadra con el input de una función, lo que se puede hacer es
> correr algo en comptime que depende de lo que devuelva cumpla o no la
> interface.


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


### Silently ignoring return values

As in zig, you cannot silently ignore return values. You have to use `_` to ignore them.

```zig
_ = my_function()
```

