_HashSetValue: Type = ()

implement ImplicitlyCopyable#(_HashSetValue) ()

HashSet := #(.key: Type, .policy: Type: HashPolicy#(policy, key) = StandardHashPolicy) (
    ._map : HashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

_init_hash_set := #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator
) (.policy: policy, .allocator: $&Provider, .capacity: UIntNative) -> (
    .result : Errable#(HashSet#(.key: key, .policy: policy), (..out_of_memory))
) {
    map ::= _init_hash_map#(.key: key, .value: _HashSetValue)(
        .policy = ~policy, .allocator = allocator, .capacity = capacity
    )!
    result = ..ok(._map = ~map)
}

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator) Init#(
    HashSet#(.key: key, .policy: policy),
    (.policy: policy, .allocator: $&Provider, .capacity: UIntNative = 8)
) (
    .Result : Type = Errable#(HashSet#(.key: key, .policy: policy), (..out_of_memory))
    .init   = (.args: (.policy: policy, .allocator: $&Provider, .capacity: UIntNative = 8)) -> (
        .result : Result
    ) {
        constructed ::= _init_hash_set#(.key: key)(
            .policy = ~args.policy, .allocator = args.allocator, .capacity = args.capacity
        )!
        result = ..ok ~constructed
    }
)

implement#(.key: Type: _StandardHashKey#(key), .Provider: Type: Allocator) Init#(
    HashSet#(.key: key, .policy: StandardHashPolicy),
    (
        .policy    : StandardHashPolicy = StandardHashPolicy(),
        .allocator : $&Provider,
        .capacity  : UIntNative         = 8
    )
) (
    .Result : Type = Errable#(
        HashSet#(.key: key, .policy: StandardHashPolicy), (..out_of_memory)
    )
    .init = (
        .args : (
            .policy    : StandardHashPolicy = StandardHashPolicy(),
            .allocator : $&Provider,
            .capacity  : UIntNative         = 8
        )
    ) -> (.result: Result) {
        constructed ::= _init_hash_set#(.key: key)(
            .policy = ~args.policy, .allocator = args.allocator, .capacity = args.capacity
        )!
        result = ..ok ~constructed
    }
)

_map_insert_hash_set := #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) (.self: $&HashSet#(.key: key, .policy: policy), .key: key, .allocator: $&Provider) -> (
    .result : Errable#(Bool, (..out_of_memory))
) {
    query ::= HashPolicy#(policy, key).query(&self&._map._policy, .key = &key)
    if contains(&self&._map, .key = query).ok {
        _hash_discard(.value = ~key, .allocator = allocator)
        result = ..ok false
        return
    }

    put(.self = $&self&._map, .key = ~key, .value = _HashSetValue(), .allocator = allocator)!

    result = ..ok true
}

_map_contains_hash_set := #(.key: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self: &HashSet#(.key: key, .policy: policy), .key: HashPolicy#(policy, key).Query
) -> (.ok: Bool) { ok = contains(&self&._map, .key = key).ok }

_map_remove_hash_set := #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) (
    .self      : $&HashSet#(.key: key, .policy: policy),
    .key       : HashPolicy#(policy, key).Query,
    .allocator : $&Provider
) -> (.removed: Bool) {
    removed = remove(.self = $&self&._map, .key = key, .allocator = allocator).removed
}

_map_extract_hash_set := #(.key: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self: $&HashSet#(.key: key, .policy: policy), .key: HashPolicy#(policy, key).Query
) -> (.result: ?key) {
    match extract($&self&._map, .key = key).result {
        ..none { result = ..none }
        ..some ~payload {
            entry ::= ~payload.value
            result = ..some(.value = ~entry.key)
        }
    }
}

_collection_length_hash_set := #(.key: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self : &HashSet#(.key: key, .policy: policy)
) -> (.count: UIntNative) { count = length(&self&._map).count }

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) CollectionLength#(
    HashSet#(.key: key, .policy: policy)
) (
    .measure_length = _collection_length_hash_set
)

_collection_capacity_hash_set := #(.key: Type, .policy: Type: HashPolicy#(policy, key)) (
    .self : &HashSet#(.key: key, .policy: policy)
) -> (.count: UIntNative) {
    count = capacity(&self&._map).count
}

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) CollectionCapacity#(
    HashSet#(.key: key, .policy: policy)
) (
    .measure_capacity = _collection_capacity_hash_set
)

_map_reserve_hash_set := #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) (.self: $&HashSet#(.key: key, .policy: policy), .capacity: UIntNative, .allocator: $&Provider) -> (
    .result : Errable#(Void, (..out_of_memory))
) {
    result = reserve($&self&._map, .capacity = capacity, .allocator = allocator)
}

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) Deinit#(
    HashSet#(.key: key, .policy: policy)
) (
    .deinit = (.self: $&HashSet#(.key: key, .policy: policy)) -> () {
        deinit(.self = $&self&._map)
    }
)
