## Concurrency

**No hay async functions**.

Hay dos tipos de threads:

- OS-threads
	Gestionados por el sistema operativo.
	Pesados.
- Light-threads
	(como las goroutines)
	Muchísimos más ligeros.
	Requieren un runtime que multiplexe los recursos entre distintas tareas.

> [!TODO]
> Elección de preemtive vs cooperative en light threads.

Ambos ofrecen una experiencia homogenea (aunque igual hay que hacer dos variantes de todos los primitivos)


### Thread safety

Para garantizar la thread safety, tendremos los punteros exclusivos ~&, que se debe garantizar que sean los únicos punteros a la memoria que apuntan.

> Algo como lo de rust, solo que al hacer un nuevo tipo de puntero en lugar de extender esta norma a los punteros mutables normales, no perjudicamos tanto la ergonomía.

A un thread solo se le pueden pasar punteros exclusivos, o referencias de solo lectura, o punteros a mutexes o canales.
(Esto incluye las closures)

> [!TODO]
> Pensar como interactúan todos los elementos de threads con punteros, mutexes...
> Darle una vuelta a este punto


### OS threads


```
th := system.process_manager | spawn_thread($&_, {  -- type is ThreadHandler
	...
})

th | wait(_)

-- Con funciones
th := system.process_manager | spawn_thread($&_, my_function, (x, y, z))

-- Lanzar un bucle infinito
th := system.process_manager | spawn_thread($&_,  {
	loop {

	}
})

-- Lanzar múltiples procesos en bucle
for i in 1..10 {
	system.process_manager | spawn_thread($&_, {
		-- Aquí puedes usar i
		...
	})
}

wait_all_threads
```


### Light threads

El runtime se encarga de:
- **Multiplexar tareas:** Distribuir las tareas entre los OS threads disponibles.
- **Balanceo de carga:** Reasignar tareas si un OS thread queda inactivo.
- **Sincronización:** Proveer primitivas (como wait groups o canales) para coordinar tareas y recoger resultados.

```
lcr := LightConcurrencyRuntime (.threads = 4)

lcr | spawn_thread ($&_, {
	...
})
```
 Y ese runtime que lance unos threads y que se encargue de multiplexar.
 
 Está bien que sea una global. Así el acceso es fácil, pero quienes lo usen tendrán que marcar con un $ su función, porque tiene side effects.

### Sintaxis

El criterio de tener que declarar fuera cualquier cosa que queramos usar fuera es muy coherente con como son las branches.

>[!QUESTION]
>Lo único que no habría que permitir closures, porque no está claro como se va a comportar no?

Tiene sentido no permitir que el input no sean deep_copies o mutex o channels? La mutabilidad como se gestiona?

>[!ERROR]
>En go las goroutines no puedes return. Eso es una asyn func.
>Igual la clave es encontrar una sintaxis que me permita hacer algo similar de forma sencilla.


#### Channels

```
Channel<#T: Type> : Type
```

```
funcion_enviadora (c:Channel) -> () := {
	time | sleep (&_, 1000)
	c | send (_, 42)
}

canal : Channel<Int>

for i in 1..10 {
	lcr | spawn_thread ($&_, funcion_enviadora, (canal))
}

loop {
	print(canal|receive)
}
```

En go hay dos tipos de canales:
- Sin buffer. Cuando hay un dato, la entrada está bloqueada hasta que alguien lo consuma.
- Con buffer. Se comporta como una cola de longitud determinada.

Igual haría que hubiera tres tipos:
- Spot (one seat)
- Queue (FIFO)
- Stack (LIFO)

```
Channel<T> : Abstract = (
    put(T)
    get() -> T
)
Channel canbe (Spot, Queue, Stack)
Channel defaults Spot


Queue<T> : Abstract = (
	put T -> ()
	get [) -> T
)
Queue canbe (DynamicQueue, StaticQueue<n>)
Queue defaults DynamicQueue

Stack<T> : Abstract = (
	put T -> [)
	get () -> T
)
Stack canbe (DynamicStack, StaticStack<n>)
Stack defaults DynamicStack

```

```
channel: Channel

channel|put("message")
print(channel|get)
```

```
a: Spot(Int)
branch {
	a|put funcion 1
}

b: Spot(Int)
branch {
	b|put funcion 2
}

c = a|get + b|get
```

#### Mutex

Lo ofrece el OS.

```
estado : Mutex<Int>

incrementar($&estado) := {
	estado|lock
	estado++
	estado|unlock
}

for 1..10 spawn_thread({
	incrementar($&estado)
})
```

> [!IDEA] Automutex
> ```
> estado : AutoMutex<Int>
> 
> incrementar($&estado) := {
> 	estado++
> }
> 
> for 1..10 spawn_thread({
> 	incrementar($&estado)
> })
> ```

#### RW Lock

En una charla de zig sobre concurrencia (https://www.youtube.com/watch?v=x1N9JPPPC18&list=WL&index=3) dice que es mejor usar RW locks que mutexes, porque los lectores solo bloquean a los escritores, y no a otros lectores.


#### Semaphores


#### Lock and unlock

Se podría hacer igual que con init y deinit y alloc y dealloc. Que todo lo que hagas lock tengas que hacer unlock.


### Wait groups

```
wg := lcr | new_waitgroup()  -- of type WaitGroupHandler

wg | branch({
	...
})

wg | wait()
```

