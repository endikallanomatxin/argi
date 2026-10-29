_HashSetValue: Type = ()

implement ImplicitlyCopyable#(_HashSetValue) ()

HashSet := #(.key: Type, .policy: Type: HashPolicy#(policy, key) = StandardHashPolicy) (
    ._map : HashMap#(.key: key, .value: _HashSetValue, .policy: policy)
)

_init_hash_set := #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator
) (
    .policy       : policy,
    .allocator    : $&Provider,
    .capacity     : UIntNative,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(HashSet#(.key: key, .policy: policy), (..out_of_memory))) {
    assume error_tracer

    map ::= _init_hash_map#(.key: key, .value: _HashSetValue)(
        .policy = ~policy, .allocator = allocator, .capacity = capacity
    )!
    result = ..ok(._map = ~map)
}

HashSetInitArgs: Type = #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator
) (
    .policy    : policy,
    .allocator : $&Provider,
    .capacity  : UIntNative  = 8
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator) Init#(
    HashSet#(.key: key, .policy: policy), HashSetInitArgs#(key, policy, Provider)
) (
    .Result : Type = Errable#(HashSet#(.key: key, .policy: policy), (..out_of_memory))

    .init = HashSetInitArgs#(key, policy, Provider) -> (.result: Result) {
        assume error_tracer

        constructed ::= _init_hash_set#(.key: key)(
            .policy = ~policy, .allocator = allocator, .capacity = capacity
        )!
        result = ..ok ~constructed
    }
)

StandardHashSetInitArgs: Type = #(
    .key: Type: _StandardHashKey#(key), .Provider: Type: Allocator
) (
    .allocator : $&Provider,
    .capacity  : UIntNative  = 8
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.key: Type: _StandardHashKey#(key), .Provider: Type: Allocator) Init#(
    HashSet#(.key: key, .policy: StandardHashPolicy), StandardHashSetInitArgs#(key, Provider)
) (
    .Result : Type = Errable#(
        HashSet#(.key: key, .policy: StandardHashPolicy), (..out_of_memory)
    )

    .init = StandardHashSetInitArgs#(key, Provider) -> (.result: Result) {
        assume error_tracer

        constructed ::= _init_hash_set#(.key: key)(
            .policy = StandardHashPolicy(), .allocator = allocator, .capacity = capacity
        )!
        result = ..ok ~constructed
    }
)

_map_insert_hash_set := #(
    .key: Type, .policy: Type: HashPolicy#(policy, key), .Provider: Type: Allocator#(Provider)
) (
    .self         : $&HashSet#(.key: key, .policy: policy),
    .key          : key,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Bool, (..out_of_memory))) {
    assume error_tracer

    assume allocator
    incoming ::= ~key
    query ::= HashPolicy#(policy, key).query(&self&._map._policy, .key = &incoming)
    if contains(&self&._map, .key = query).ok {
        result = ..ok false
        return
    }

    put(
        .self = $&self&._map, .key = ~incoming, .value = _HashSetValue(), .allocator = allocator
    )!

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
) (
    .self         : $&HashSet#(.key: key, .policy: policy),
    .capacity     : UIntNative,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..out_of_memory))) {
    assume error_tracer

    result = reserve($&self&._map, .capacity = capacity, .allocator = allocator)
}

implement#(.key: Type, .policy: Type: HashPolicy#(policy, key)) Deinit#(
    HashSet#(.key: key, .policy: policy)
) (
    .deinit = (.self: $&HashSet#(.key: key, .policy: policy)) -> () {
        deinit(.self = $&self&._map)
    }
)
