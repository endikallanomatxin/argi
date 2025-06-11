Maps (array_hash_map, hash_map, static_string_map)
	ArrayHashMap
	ArrayHashMapUnmanaged
	AutoArrayHashMap
	AutoArrayHashMapUnmanaged
	AutoHashMap
	AutoHashMapUnmanaged
	BufMap
	EnumMap
	HashMap
	HashMapUnmanaged
	StaticStringMap
	StaticStringMapWithEql
	StringArrayHashMap
	StringArrayHashMapUnmanaged
	StringHashMap
	StringHashMapUnmanaged

##### Maps

Value puede o no ser heterogéneo (`Any`). El key no puede nunca ser heterogéneo. 
_(Esto es una limitación artificial para evitar código mierdoso. En go por ejemplo no se puede y no entiendo en qué contexto podría ser útil. Mejor evitarlo.)_
Si se pone un abstract con default, entonces se tomará como el tipo del key.

```
-- Un típico dict
notas : Map<String, Int> = [
	"Mikel"=8
	"Jon"=9
]
```

Por defecto si haces:
```
notas := ["Mikel"=8, "Jon"=9]
```
infiere los tipos.

