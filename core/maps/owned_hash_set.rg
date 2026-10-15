OwnedHashSet#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)): Type = (
    ._map : OwnedHashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

implement#(
    .key: Type, .policy: Type: BorrowedHashPolicy#(policy, key), .Provider: Type: Allocator
) Init#(
    OwnedHashSet#(.key: key, .policy: policy),
    (.policy: policy, .allocator: $&Provider = reach allocator, .capacity: UIntNative = 8)
) (
    .Result : Type = Errable#(OwnedHashSet#(.key: key, .policy: policy), (..out_of_memory))
    .init   = (
        .args : (
            .policy: policy, .allocator: $&Provider = reach allocator, .capacity: UIntNative = 8
        )
    ) -> (.result: Result) {
        policy ::= ~args.policy
        allocator ::= args.allocator
        capacity ::= args.capacity

        assume allocator
        constructed :: OwnedHashSet#(.key: key, .policy: policy)
        map ::= OwnedHashMap#(.key: key, .value: _HashSetValue, .policy: policy)(
            .policy = ~policy, .allocator = allocator, .capacity = capacity
        )!
        constructed = (._map = ~map)

        result = ..ok ~constructed
    }
)

_map_insert_owned_hash_set#(
    .key      : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) := (.self: $&OwnedHashSet#(.key: key, .policy: policy), .key: key, .allocator: $&Provider) -> (
    .result : Errable#(Bool, (..out_of_memory))
) {
    if contains(&self&._map, .key = &key).ok {
        _owned_hash_discard(.value = ~key, .allocator = allocator)
        result = ..ok false
        return
    }

    put(.self = $&self&._map, .key = ~key, .value = _HashSetValue(), .allocator = allocator)!

    result = ..ok true
}

_map_contains_owned_hash_set#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) := (
    .self: &OwnedHashSet#(.key: key, .policy: policy), .key: &key
) -> (.ok: Bool) { ok = contains(&self&._map, .key = key).ok }

_map_remove_owned_hash_set#(
    .key      : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) := (.self: $&OwnedHashSet#(.key: key, .policy: policy), .key: &key, .allocator: $&Provider) -> (
    .removed : Bool
) { removed = remove(.self = $&self&._map, .key = key, .allocator = allocator).removed }

_map_extract_owned_hash_set#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) := (
    .self: $&OwnedHashSet#(.key: key, .policy: policy), .key: &key
) -> (.result: ?key) {
    match extract($&self&._map, .key = key).result {
        ..none { result = ..none }
        ..some ~payload {
            entry ::= ~payload.value
            result = ..some(.value = ~entry.key)
        }
    }
}

_collection_length_owned_hash_set#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key))(
    .self : &OwnedHashSet#(.key: key, .policy: policy)
) -> (.count: UIntNative) := { count = length(&self&._map).count }

implement#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) CollectionLength#(
    OwnedHashSet#(.key: key, .policy: policy)
) (
    .measure_length = _collection_length_owned_hash_set
)

_collection_capacity_owned_hash_set#(
    .key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)
)(.self: &OwnedHashSet#(.key: key, .policy: policy)) -> (.count: UIntNative) := {
    count = capacity(&self&._map).count
}

implement#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) CollectionCapacity#(
    OwnedHashSet#(.key: key, .policy: policy)
) (
    .measure_capacity = _collection_capacity_owned_hash_set
)

_map_reserve_owned_hash_set#(
    .key      : Type,
    .policy   : Type: BorrowedHashPolicy#(policy, key),
    .Provider : Type: Allocator#(Provider)
) := (
    .self      : $&OwnedHashSet#(.key: key, .policy: policy),
    .capacity  : UIntNative,
    .allocator : $&Provider
) -> (.result: Errable#(Void, (..out_of_memory))) {
    result = reserve($&self&._map, .capacity = capacity, .allocator = allocator)
}

implement#(.key: Type, .policy: Type: BorrowedHashPolicy#(policy, key)) Deinit#(
    OwnedHashSet#(.key: key, .policy: policy)
) (
    .deinit = (.self: $&OwnedHashSet#(.key: key, .policy: policy)) -> () {
        deinit(.self = $&self&._map)
    }
)
