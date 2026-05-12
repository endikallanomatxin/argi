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
for i in Range(.start = 1, .end = 10) {
	system.process_manager | spawn_thread($&_, {
		-- Aquí puedes usar i
		...
	})
}

wait_all_threads
```
