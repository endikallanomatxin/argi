# Funciones

Functions are first class citizen.

##### Function definition syntax

```
add(a: Int, b: Int) ::= Int {
	return a+b
}
```

return variables are initialized (to zero) if named.

```
calculate_stats(list: List) ::= (mean: Float, standard_deviation: Float) {
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
) ::= (
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
!&var -- mutable pointer
```

La sintaxis básica para pasar punteros 

```
funcion_que_recibe_puntero(p_datos: Ptr<Map<String,Int>>) ::= {
	-- Aquí se usa: p_datos
	-- Es un puntero
	...
}

funcion_que_recibe_puntero(&datos)
```

Para hacer la de-referencia automática, se hace así:

```
funcion_que_lee(&datos: Map<String,Int>) ::= {
	-- Aquí se usa: datos
	-- Es un map
	...
}

funcion_que_lee(&datos)
```

Pero no deja mutar lo que hay al otro lado del puntero. Si se quiere mutar el valor hay que pasar con un indicador de que es una referencia mutable:

```
funcion_que_escribe(!&datos: Map<String,Int>) ::= {
	-- Aquí se usa: datos
	-- Es un map
	...
}

funcion_que_escribe(!&datos)
```

Hacer esto bien hace que no haga falta decir si las funciones son puras o tienen side effects.



#### Side effects

If a function has side effects, it requires marking with `!`, and it propagates.

> [!BUG]
> Esto va a hacer que printf("Hello, world\n") tenga side effects.
> NO PODEMOS PERMITIR QUE EDITAR UN ARCHIVO NO SE CONSIDERE UN SIDE EFFECT.
> Podemos hacer:
> - Que efectivamente printf! tenga side effects y haga que las funciones que lo usan también lo tengan.
>   Pero esto hará function coloring.
> - DEPENDENCY INJECTION: Que haya que abrir el archivo de IO y pasarselo a aquellas funciones que quieran imprimir.
>   Pero esto igual es demasiado tedioso.

Chagpt:
Esto se conoce generalmente como "programación basada en capacidades" o, en contextos más amplios, como inyección de dependencias para el manejo de efectos secundarios. La idea es que en lugar de depender de variables globales o funciones "impuras", se pasa explícitamente un objeto (o "handle") que representa la capacidad de realizar cierta operación (como E/S, acceso a bases de datos, etc.), haciendo que la función se mantenga lo más pura posible en cuanto al estado global.
El compilador podría decirte al hacer audit, si ve que hay muchas funciones con side effects, entonces te avisa de que hay un problema de diseño. Y que le eches un ojo a lo que es la dependency injection.


Así quedaría si hubiera que abrir los archivos al principio y pasarlos como argumentos.

```rg
-- Importamos la librería de IO
import stdioe
import fs


main! ::= {
	-- Creamos un archivo de IO
	stdi, stdo, stde := stdioe.open_buffers()

	file = file.Open()

	-- Llamada a una función pura que imprime
	do_something_pure(123, log = !&file)
}

-- Podemos usar el hecho de que tome stdo para controlar si queremos que imprima.
do_something_pure(a: Int, !&log: !&Buffer? = null) ::= {
	if log { log|write("Hello, world\n") }
}

do_something_pure(a: Int, !&log: !&Buffer) ::= {
	log|write("Hello, world\n")
}
```
Una cosa buena es que hace fácil hacer todo el log a un archivo de logueo.

(Hacer el printf debuggin un poco más complicado en realidad hará que la gente use más asserts. Pero el assert, a donde imprime?)

Assert debería ser una función pura? Yo creo que sí, porque tras modificar el estado crashea.


O una keyword debug que ignore los side effects.

```rg
do_something_pure(a: Int) ::= {
	debug { io.std.out!()|write("Hello, world\n") }
}
```

Con un shortcut para eso:

```rg
debug_print("Hello, world")
```

o igual

```rg
debug print!("Hello, world")
```


> [!TODO]
> Esta es la solución que más me gusta.
> Pensar si debug se va a usar para otras cosas.
> Si sí, me parece bien que uno de sus efectos sea que ignore los side effects.
> Si no, igual eso debería ser una keyword diferente: `pure`, `ignore`, `ignore_side_effects` o algo así.
> O igual el hecho de que eso solo está pensado para debugging da información útil. Te hace ver que eso no debería estar en producción.
> Igual tanto `assert` como `ignore_side_effects` deberían ser parte del módulo debug.


From D:
There is the debug keyword together with the the -debug compiler switch. You can disable your print commands with this switch without deleting them. Consider the following code snippet.

```d
writeln("Hello");
debug writeln("World");
```
If compiled without -debug, it will print only “Hello”. However, compiled with -debug, it will also print “World”.


Para acceder a una base de datos:

```rg
import db

main! ::= {
	-- Creamos una conexión a la base de datos
	db_conn = db.open_database("my_db")

	-- Llamada a una función pura que consulta la base de datos
	user = query_user(!&db_conn, 123)
}

query_user(!&db_conn: !&DbConnection, user_id:: Int) ::= User? {
	-- Acceso a la db
	row = db_conn|execute(!&_, "SELECT * FROM user WHERE id = ?", user_id)
	if row == null {
		return null
	}
	user = parse_user(row)
	return user
}
```


HEEEYY
> [!BUG]
> Podría ser un problema para las librerías el hecho de usar ! o no.
> Realmente te obliga a poner !?
> Porque eso hace que si una librería cambia funciones de puras a impuras o viceversa el código deja de ser compilable.
> Pensar en esto!!!
> Igual lo mejor es que sea una marca que se ignora (compila igual) Solo que cuando estás programando automáticamente se actualiza, y te sirve.


##### Closures

Cuando una función accede a variables de un scope exterior, tiene que indicarlo con un `!`.

```
variable := 4

contador! ::= {
	variable++
}

contador!()  -- variable = 5
```

Así queda claro (y con una sintaxis similar a la de los argumentos) si una función tiene side effects.

Cuando se acceden constantes o definiciones de funciones exteriores, no hace falta indicarlo, es solo para variables. Así no es problema usar librerías, por ejemplo.

_(En realidad, me gustaría prohibir las closures (me parecen un poco antipattern). Pero bueno, con identificarlas claramente igual vale.)_


>[!TODO] Si dentro capturas por referencia de solo lectura? Eso habría que indicarlo?



### Dispatch

Multiple dispatch como Julia.

Te permite funcionamiento similar al del static dispatch por objetos, pero de una forma más flexible.

Da error cuando hay ambigüedad en especificidad, pero se encarga el compilador de evitarlo.

En go, no se puede definir métodos de struct de otros paquetes. Eso es una mierda!


### Operator overloading

```
operator + (v1: Vector, v2: Vector) ::= (Vector) {
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
my_var|my_func(&_)              -- o my_var|&|my_func
my_var|my_func(&_, second_arg)  -- o my_var|&|my_func(_, second_arg)
```


### NO OOP

No hay objetos.

Para dar la comodidad de llamar a métodos de objetos con un punto, se puede usar el pipe operator.

```
obj | method  -- como hacer obj.method()
```

Para recibir referencias a métodos, se usa el pipe operator con un ampersand.

```
length(&v: Vector) ::= Float {
    return sqrt(v.x^2 + v.y^2 + v.z^2)
}

my_vect = Vector(1, 2, 3)
my_vect|&|length
```


Para hacer el análogo \_\_init\_\_:

```
Expr :: Type = struct [
    ---
    An expression type for symbolic stuff
    ---
    _s:   String -- The string the user put
    _ast: Tree   -- The AST generated by the program
]

init(#t:: Type == Expr, s: String) ::= Expr {
    ast = create_ast_from_sym_s(s)
    return Expr(s, ast)
}

my_expr :: Expr = "x^2"
```

Con más info en el nombre si requieren desambiguación:

```
Vector :: Type = struct [
    x: Float
    y: Float
    z: Float
]

new_vector_cartesian(x: Float, y: Float, z: Float) ::= Vector {
    return Vector(x, y, z)
}

new_vector_from_polar(r: Float, theta: Float) ::= Vector {
    x = r * cos(theta)
    y = r * sin(theta)
    z = 0
    return Vector(x, y, z)
}

my_vect = new_vector_from_polar(2, PI)
```

Para definir el comportamiento de operadores, se usa operator overloading

```plaintext
operator + (v1: Vector, v2: Vector) ::= Vector {
    return Vector(v1.x + v2.x, v1.y + v2.y)
}
```


Para definir como se convierten en strings u otros castings.

```
to(v:: Vector, #s::== String) ::= String {
    return "Vector(" + v.x + ", " + v.y + ", " + v.z + ")"
}

my_vec|to(String)
```


### Indexables

Como ofrecer la sintaxis de \[\], para que la gente la implemente en sus tipos.
En python es \_\_getitem\_\_ y \_\_setitem\_\_. Para numpy por ejemplo.
Go no tiene de estos, igual se puede prescindir.

```
Indexable(T: Type) ::= abstract [
    operator get[](index: Int) :: T
    operator set[](index: Int, value: T)
]
```


```
Milista :: Type = struct [
    elementos: List(Int)
]

operator get[](my_list: Milista, index: Int) ::= Int {
    return my_list.elementos[index]
}

operator set[](my_list: Milista, index: Int, value: Int) {
    my_list.elementos[index] = value
}

Indexable canbe Milista
```

```
my_list :: Milista = [1, 2, 3]
print(lista[0])  -- Llama a `get`
lista[1] = 25    -- Llama a `set`
```

O igual se puede hacer con operator overloading.
