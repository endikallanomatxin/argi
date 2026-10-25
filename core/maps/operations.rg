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

MapInsertion#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Key   : Type
    .Value : Type
    .put   : (.self: $&Map, .key: Key, .value: Value, .allocator: $&Provider) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
)

MapRemoval#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Query : Type
    MapQuery#(.Map: Map, .Query: Query)
    .remove : (.self: $&Map, .key: Query, .allocator: $&Provider) -> (.removed: Bool)
)

SetInsertion#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Key    : Type
    .insert : (.self: $&Map, .key: Key, .allocator: $&Provider) -> (
        .result : Errable#(Bool, (..out_of_memory))
    )
)

MapReservation#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .reserve : (.self: $&Map, .capacity: UIntNative, .allocator: $&Provider) -> (
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
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapRemoval#(HashMap#(.key: key, .value: value, .policy: policy), Provider) (
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
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapInsertion#(HashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .Key   : Type = key
    .Value : Type = value
    .put   = _map_put_hash_map
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapReservation#(HashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .reserve = _map_reserve_hash_map
)

implement#(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) MapReservation#(HashSet#(.key: key, .policy: policy), Provider) (
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
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) MapRemoval#(HashSet#(.key: key, .policy: policy), Provider) (
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
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) SetInsertion#(HashSet#(.key: key, .policy: policy), Provider) (
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
