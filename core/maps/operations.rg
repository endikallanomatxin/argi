-- Key and value context comes from the selected nominal container, not literals.
MapLookup#(.Map: Type): Contract = (
    .Key   : Type
    .Value : Type
    .get   : (.self: &Map, .key: Key) -> (.result: ?Value)
)

StringMapLookup#(.Map: Type, .Query: Type: StringMapKey#(Query)): Contract = (
    .Value : Type
    .get   : (.self: &Map, .key: Query) -> (.result: ?Value)
)

MapMembership#(.Map: Type): Contract = (
    .Key      : Type
    .contains : (.self: &Map, .key: Key) -> (.ok: Bool)
)

TextMapMembership#(.Map: Type): Contract = (
    .contains : (.self: &Map, .key: StringView) -> (.ok: Bool)
)

MapBorrowedLookup#(.Map: Type): Contract = (
    .Key : Type
    .Value         : Type
    .get_reference : (.self: &Map, .key: Key) -> (.result: ?&Value)
)

TextMapBorrowedLookup#(.Map: Type): Contract = (
    .Value         : Type
    .get_reference : (.self: &Map, .key: StringView) -> (.result: ?&Value)
)

MapInsertion#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Key   : Type
    .Value : Type
    .put   : (.self: $&Map, .key: Key, .value: Value, .allocator: $&Provider = reach allocator) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
)

StringMapInsertion#(
    .Map      : Type,
    .Query    : Type: StringMapKey#(Query),
    .Provider : Type: Allocator#(Provider)
): Contract = (
    .Value : Type
    .put   : (.allocator: $&Provider = reach allocator, .self: $&Map, .key: Query, .value: Value) -> (
    )
)

MapRemoval#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Key    : Type
    .remove : (.self: $&Map, .key: Key, .allocator: $&Provider = reach allocator) -> (
        .removed : Bool
    )
)

SetInsertion#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .Key    : Type
    .insert : (.self: $&Map, .key: Key, .allocator: $&Provider = reach allocator) -> (
        .result : Errable#(Bool, (..out_of_memory))
    )
)

MapReservation#(.Map: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    .reserve : (.self: $&Map, .capacity: UIntNative, .allocator: $&Provider = reach allocator) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
)

MapExtraction#(.Map: Type): Contract = (
    .Key     : Type
    .Result  : Type
    .extract : (.self: $&Map, .key: Key) -> (.result: Result)
)

implement#(.value: Type, .Query: Type: StringMapKey#(Query)) StringMapLookup#(
    StringHashMap#(.value: value), Query
) (
    .Value : Type = value
    .get   = _map_get_StringHashMap
)

implement#(
    .value: Type, .Provider: Type: Allocator#(Provider), .Query: Type: StringMapKey#(Query)
) StringMapInsertion#(StringHashMap#(.value: value), Query, Provider) (
    .Value : Type = value
    .put   = _map_put_StringHashMap
)

implement#(.value: Type) TextMapBorrowedLookup#(
    OwnedHashMap#(.key: String, .value: value, .policy: StringHashPolicy)
) (
    .Value         : Type = value
    .get_reference = _map_get_reference_owned_string_lookup
)

implement#(.value: Type) TextMapMembership#(
    OwnedHashMap#(.key: String, .value: value, .policy: StringHashPolicy)
) (
    .contains = _map_contains_owned_string_lookup
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapRemoval#(OwnedHashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .Key    : Type = &key
    .remove = _map_remove_owned_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) MapExtraction#(
    OwnedHashMap#(.key: key, .value: value, .policy: policy)
) (
    .Key     : Type = &key
    .Result  : Type = ?OwnedHashMapEntry#(.key: key, .value: value)
    .extract = _map_extract_owned_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) MapBorrowedLookup#(
    OwnedHashMap#(.key: key, .value: value, .policy: policy)
) (
    .Key : Type = &key
    .Value         : Type = value
    .get_reference = _map_get_reference_owned_hash_map
)

implement#(.key: Type, .value: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) MapMembership#(
    OwnedHashMap#(.key: key, .value: value, .policy: policy)
) (
    .Key      : Type = &key
    .contains = _map_contains_owned_hash_map
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapInsertion#(OwnedHashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .Key   : Type = key
    .Value : Type = value
    .put   = _map_put_owned_hash_map
)

implement#(
    .key      : Type,
    .value    : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapReservation#(OwnedHashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .reserve = _map_reserve_owned_hash_map
)

implement#(
    .key      : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapReservation#(OwnedHashSet#(.key: key, .policy: policy), Provider) (
    .reserve = _map_reserve_owned_hash_set
)

implement#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) MapExtraction#(
    OwnedHashSet#(.key: key, .policy: policy)
) (
    .Key     : Type = &key
    .Result  : Type = ?key
    .extract = _map_extract_owned_hash_set
)

implement#(
    .key      : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapRemoval#(OwnedHashSet#(.key: key, .policy: policy), Provider) (
    .Key    : Type = &key
    .remove = _map_remove_owned_hash_set
)

implement#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) MapMembership#(
    OwnedHashSet#(.key: key, .policy: policy)
) (
    .Key      : Type = &key
    .contains = _map_contains_owned_hash_set
)

implement#(
    .key      : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) SetInsertion#(OwnedHashSet#(.key: key, .policy: policy), Provider) (
    .Key    : Type = key
    .insert = _map_insert_owned_hash_set
)

implement#(
    .key      : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapRemoval#(HashSet#(.key: key, .policy: policy), Provider) (
    .Key    : Type = key
    .remove = _map_remove_hash_set
)

implement#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)) MapMembership#(
    HashSet#(.key: key, .policy: policy)
) (
    .Key      : Type = key
    .contains = _map_contains_hash_set
)

implement#(
    .key      : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) SetInsertion#(HashSet#(.key: key, .policy: policy), Provider) (
    .Key    : Type = key
    .insert = _map_insert_hash_set
)

implement#(
    .key      : Type: ImplicitlyCopyable,
    .value    : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapRemoval#(HashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .Key    : Type = key
    .remove = _map_remove_hash_map
)

implement#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key)
) MapBorrowedLookup#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .Key : Type = key
    .Value         : Type = value
    .get_reference = _map_get_reference_hash_map
)

implement#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key)
) MapMembership#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .Key      : Type = key
    .contains = _map_contains_hash_map
)

implement#(
    .key    : Type: ImplicitlyCopyable,
    .value  : Type: ImplicitlyCopyable,
    .policy : Type: HashPolicy#(policy, key)
) MapLookup#(HashMap#(.key: key, .value: value, .policy: policy)) (
    .Key   : Type = key
    .Value : Type = value
    .get   = _map_get_hash_map
)

implement#(
    .key      : Type: ImplicitlyCopyable,
    .value    : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) MapInsertion#(HashMap#(.key: key, .value: value, .policy: policy), Provider) (
    .Key   : Type = key
    .Value : Type = value
    .put   = _map_put_hash_map
)
