_HashSetValue: Type = ()

implement ImplicitlyCopyable#(_HashSetValue) ()

-- Membership uses the map's collision handling, storage, and key lifetimes.
HashSet#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)): Type = (
    ._map : HashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

implement#(
    .key      : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator
) Init#(
    HashSet#(.key: key, .policy: policy),
    (.policy: policy, .allocator: $&Provider = reach allocator, .capacity: UIntNative = 8)
) (
    .Result : Type = Errable#(HashSet#(.key: key, .policy: policy), (..out_of_memory))
    .init   = (
        .args : (
            .policy: policy, .allocator: $&Provider = reach allocator, .capacity: UIntNative = 8
        )
    ) -> (.result: Result) {
        policy ::= ~args.policy
        allocator ::= args.allocator
        capacity ::= args.capacity

        constructed :: HashSet#(.key: key, .policy: policy)

        map ::= HashMap#(.key: key, .value: _HashSetValue, .policy: policy)(
            .policy = ~policy, .allocator = allocator, .capacity = capacity
        )!
        constructed = (._map = ~map)

        result = ..ok ~constructed
    }
)

_map_insert_hash_set#(
    .key      : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) := (.self: $&HashSet#(.key: key, .policy: policy), .key: key, .allocator: $&Provider) -> (
    .result : Errable#(Bool, (..out_of_memory))
) {
    if contains(&self&._map, .key = key).ok {
        result = ..ok false
        return
    }

    put(.self = $&self&._map, .key = key, .value = _HashSetValue(), .allocator = allocator)!

    result = ..ok true
}

_map_contains_hash_set#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)) := (
    .self: &HashSet#(.key: key, .policy: policy), .key: key
) -> (.ok: Bool) {
    ok = contains(&self&._map, .key = key).ok
}

_map_remove_hash_set#(
    .key      : Type: ImplicitlyCopyable,
    .policy   : Type: HashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) := (.self: $&HashSet#(.key: key, .policy: policy), .key: key, .allocator: $&Provider) -> (
    .removed : Bool
) {
    removed = remove(.self = $&self&._map, .key = key, .allocator = allocator).removed
}

_collection_length_hash_set#(
    .key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
)(.self: &HashSet#(.key: key, .policy: policy)) -> (.count: UIntNative) := {
    count = length(&self&._map).count
}

implement#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)) CollectionLength#(
    HashSet#(.key: key, .policy: policy)
) (
    .measure_length = _collection_length_hash_set
)

_collection_capacity_hash_set#(
    .key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)
)(.self: &HashSet#(.key: key, .policy: policy)) -> (.count: UIntNative) := {
    count = capacity(&self&._map).count
}

implement#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)) CollectionCapacity#(
    HashSet#(.key: key, .policy: policy)
) (
    .measure_capacity = _collection_capacity_hash_set
)

implement#(.key: Type: ImplicitlyCopyable, .policy: Type: HashPolicy#(policy, key)) Deinit#(
    HashSet#(.key: key, .policy: policy)
) (
    .deinit = (.self: $&HashSet#(.key: key, .policy: policy)) -> () {
        deinit(.self = $&self&._map)
    }
)
