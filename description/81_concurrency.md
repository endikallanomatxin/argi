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

Ambos ofrecen una experiencia homogenea (aunque igual hay que hacer dos variantes de todos los primitivos)


### OS threads

```
th := spawn_thread({  -- type is ThreadHandler
	...
})

th | wait()

-- Con funciones
th := spawn_thread(my_function(x, y, z))

-- Lanzar un bucle infinito
th := spawn_thread(
	loop {

	}
)

-- Lanzar múltiples procesos en bucle
for i in 1..10 {
	spawn_thread(
		{...}
	)
}
wait_all_threads()
```


### Light threads

El runtime se encarga de:
- **Multiplexar tareas:** Distribuir las tareas entre los OS threads disponibles.
- **Balanceo de carga:** Reasignar tareas si un OS thread queda inactivo.
- **Sincronización:** Proveer primitivas (como wait groups o canales) para coordinar tareas y recoger resultados.

```
lcr := LightConcurrencyRuntime(threads = 4)

lcr | spawn_thread ({
	...
})
```
 Y ese runtime que lance unos threads y que se encargue de multiplexar.
 
 Está bien que sea una global. Así el acceso es fácil, pero quienes lo usen tendrán que marcar con un ! su función, porque tiene side effects.

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
funcion_enviadora(canal: Channel) := {
	time|wait(1)
	canal|send("done")
}

canal : Channel<int>

for i in 1..10 {
	branch funcion_enviadora(canal)
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
Channel<T> : Abstract = [
    put(T)
    get() -> T
]
Channel canbe [Spot, Queue, Stack]
Channel defaults Spot


Queue<T> : Abstract = [
	put(T)
	get() -> T
]
Queue canbe [DynamicQueue, StaticQueue<n>]
Queue defaults DynamicQueue

Stack<T> : Abstract = [
	put(T)
	get() -> T
]
Stack canbe [DynamicStack, StaticStack<n>]
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
	a|put(funcion(1))
}

b: Spot(Int)
branch {
	b|put(funcion(2))
}

c = a|get + b|get
```

#### Mutex

Lo ofrece el OS.

```
estado : Mutex<Int>

incrementar(!&estado) := {
	estado|lock
	estado++
	estado|unlock
}

for 1..10 spawn_thread({
	incrementar(!&estado)
})
```

> [!IDEA] Automutex
> ```
> estado : AutoMutex<Int>
> 
> incrementar(!&estado) := {
> 	estado++
> }
> 
> for 1..10 spawn_thread({
> 	incrementar(!&estado)
> })
> ```


semaphores?


#### Wait groups

```
wg := lcr | new_waitgroup()  -- of type WaitGroupHandler

wg | branch({
	...
})

wg | wait()
```

