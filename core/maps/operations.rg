-- A collection has one query type shared by all its lookup operations.
MapQuery#(.Map: Type): Contract = (
    .Query : Type
    ImplicitlyCopyable#(Query)
)

MapMembership#(.Map: Type): Contract = (
    .Query : Type
    MapQuery#(.Map: Map, .Query: Query)
    .contains : (.self: &Map, .key: Query) -> (.ok: Bool)
)

MapLookup#(.Map: Type): Contract = (
    .Query : Type
    .Value : Type
    MapQuery#(.Map: Map, .Query: Query)
    .get_reference : (.self: &Map, .key: Query) -> (.result: ?&Value)
)

MutableMapLookup#(.Map: Type): Contract = (
    .Query : Type
    .Value : Type
    MapLookup#(.Map: Map, .Query: Query, .Value: Value)
    .get_mutable_reference : (.self: $&Map, .key: Query) -> (.result: ?$&Value)
)

MapLookupValue#(.Map: Type): Contract = (
    .Query : Type
    .Value : Type: ImplicitlyCopyable
    MapLookup#(.Map: Map, .Query: Query, .Value: Value)
    .get : (.self: &Map, .key: Query) -> (.result: ?Value)
)

MapInsertion#(.Map: Type): Contract = (
    .Key   : Type
    .Value : Type
    .put   : (.self: $&Map, .key: Key, .value: Value, .allocator: Virtual#(Allocator)) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
)

MapRemoval#(.Map: Type): Contract = (
    .Query : Type
    MapQuery#(.Map: Map, .Query: Query)
    .remove : (.self: $&Map, .key: Query, .allocator: Virtual#(Allocator)) -> (.removed: Bool)
)

SetInsertion#(.Map: Type): Contract = (
    .Key    : Type
    .insert : (.self: $&Map, .key: Key, .allocator: Virtual#(Allocator)) -> (
        .result : Errable#(Bool, (..out_of_memory))
    )
)

MapReservation#(.Map: Type): Contract = (
    .reserve : (.self: $&Map, .capacity: UIntNative, .allocator: Virtual#(Allocator)) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
)

MapExtraction#(.Map: Type): Contract = (
    .Query  : Type
    .Result : Type
    MapQuery#(.Map: Map, .Query: Query)
    .extract : (.self: $&Map, .key: Query) -> (.result: Result)
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) MapQuery#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .Query : Type = HashPolicy#(policy, key).Query
)

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) MapQuery#(
    HashSet#(.key: key, .policy: policy)
) (
    .Query : Type = HashPolicy#(policy, key).Query
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key)
) MapRemoval#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .Query  : Type = HashPolicy#(policy, key).Query
    .remove = _map_remove_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) MapExtraction#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .Query   : Type = HashPolicy#(policy, key).Query
    .Result  : Type = ?HashMapEntry#(.key: key, .value: value)
    .extract = _map_extract_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) MapLookup#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .Query         : Type = HashPolicy#(policy, key).Query
    .Value         : Type = value
    .get_reference = _map_get_reference_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) MutableMapLookup#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .Query                 : Type = HashPolicy#(policy, key).Query
    .Value                 : Type = value
    .get_mutable_reference = _map_get_mutable_reference_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: HashPolicy#(policy, key)) MapMembership#(
    HashMap#(.key: key, .value: value, .policy: policy)
) (
    .Query    : Type = HashPolicy#(policy, key).Query
    .contains = _map_contains_hash_map
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key)
) MapInsertion#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .Key   : Type = key
    .Value : Type = value
    .put   = _map_put_hash_map
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key)
) MapReservation#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .reserve = _map_reserve_hash_map
)

implement#(
    .key: Type, .policy: Type: HashPolicy#(policy, key)
) MapReservation#(HashSet#(.key: key, .policy: policy)) (
    .reserve = _map_reserve_hash_set
)

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) MapExtraction#(
    HashSet#(.key: key, .policy: policy)
) (
    .Query   : Type = HashPolicy#(policy, key).Query
    .Result  : Type = ?key
    .extract = _map_extract_hash_set
)

implement#(
    .key: Type, .policy: Type: HashPolicy#(policy, key)
) MapRemoval#(HashSet#(.key: key, .policy: policy)) (
    .Query  : Type = HashPolicy#(policy, key).Query
    .remove = _map_remove_hash_set
)

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) MapMembership#(
    HashSet#(.key: key, .policy: policy)
) (
    .Query    : Type = HashPolicy#(policy, key).Query
    .contains = _map_contains_hash_set
)

implement#(
    .key: Type, .policy: Type: HashPolicy#(policy, key)
) SetInsertion#(HashSet#(.key: key, .policy: policy)) (
    .Key    : Type = key
    .insert = _map_insert_hash_set
)

implement#(
    .key: Type, .value: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
) MapLookupValue#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .Query : Type = HashPolicy#(policy, key).Query
    .Value : Type = value
    .get   = _map_get_hash_map
)
