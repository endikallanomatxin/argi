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

The value may be heterogeneous (`Any`); the key must always be homogeneous.
_(This is an intentional limitation to discourage poor code. Go also disallows it, and it is unclear when heterogeneous keys would be useful.)_
If an abstract with a default is provided, that default becomes the key type.

```
-- A typical dictionary
notas : Map<String, Int> = [
	"Mikel"=8
	"Jon"=9
]
```

By default, this:
```
notas := ["Mikel"=8, "Jon"=9]
```
infers the types.
