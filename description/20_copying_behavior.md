## Source of confusion

In many languages (C, Zig, odin...), everything is passed by value.

When structs with references are passed by value, you have to consider that the
referenced data is not copied. This is a perspective change, because before
differente values were completely independent, but now the passed value can
affect the original. Having the two perspectives coexist is a source of
confusion. Besides, it forces you to know the implementation details to know
which of the two perspectives is the correct one to use.

It causes:
- Unwanted side effects.
- Double free errors.

```
m1 : Map = ()
m2 := m1
m2 | put($&_, "key", "value") -- Cambia el original

m1 | deinit($&_)
m2 | deinit($&_) -- Double free error
```

## Posible solutions

1. Allow only a single use of a variable. (explicit deep if needed)
    - Copying is more explicit.
    - Efficient is the default.

2. Always deep-copy by default. (~ for shallow copy)
    - Easier for new-comers.

3. Mandatory deep vs shallow indicator always. (@ for deep, ~ for shallow)
    (igual solo permitir shallow once, as the last use)
    - More explicit.



---
CONTINUAR TRABAJO


## Deep copy by default

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

funcion_que_lee(&datos)
```

Pero no deja mutar lo que hay al otro lado del puntero. Si se quiere mutar el
valor hay que pasar con un indicador de que es una referencia mutable:

```
funcion_que_escribe $&Map<String,Int> := {
	-- Usamos in& para desreferenciar al usarlo.
	-- Pudiendo modificar el valor al que apunta.
	...
}

funcion_que_escribe($&datos)
```

