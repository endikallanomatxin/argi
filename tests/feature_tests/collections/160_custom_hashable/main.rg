Key := (.id: Int32)

implement ImplicitlyCopyable#(Key) ()

implement Equal#(&Key, &Key) (
    .equal = (.left: &Key, .right: &Key) -> (.ok: Bool) {
        ok = left&.id == right&.id
    }
)

implement#(.State: Type: Hasher#(State)) Hashable#(Key, State) (
    .hash_into = (.key: &Key, .hasher: $&State) -> () {
        Hashable#(Int32, State).hash_into(.key = &key&.id, .hasher = hasher)
    }
)

CountingHasher := (.bytes: UIntNative = 0)

implement Hasher#(CountingHasher) (
    .write_bytes = (.self: $&CountingHasher, .bytes: ArrayView#(UInt8)) -> () {
        self&.bytes = self&.bytes + length(&bytes)
    }
    .finish = (.self: &CountingHasher) -> (.hash: UIntNative) { hash = self&.bytes }
)

CollisionPolicy: Type = ()

implement HashPolicy#(CollisionPolicy, Key) (
    .Query : Type = &Key
    .query = (.self: &CollisionPolicy, .key: &Key) -> (.query: Query) { query = key }

    .hash  = (.self: &CollisionPolicy, .key: &Key) -> (.hash: UIntNative) { hash = 0 }
    .equal = (.self: &CollisionPolicy, .left: &Key, .right: &Key) -> (.ok: Bool) {
        ok = left&.id == right&.id
    }
)

check_custom := #(.Provider: Type: Allocator) (.allocator: $&Provider) -> () {
    assume allocator
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: Key, .value: Int32)(.policy = CollisionPolicy())
    )
    unwrap_or_abort(.value = put($&map, .key = Key(.id = 9), .value = 10))
    query: Key = (.id = 9)
    match get(&map, .key = &query).result {
        ..none { abort }
        ..some item { if item.value != 10 { abort } }
    }
}

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    check_custom(.allocator = allocator)
    key: Key = (.id = 7)
    hasher :: CountingHasher = (.bytes = 0)
    Hashable#(Key, CountingHasher).hash_into(.key = &key, .hasher = $&hasher)
    if Hasher#(CountingHasher).finish(&hasher).hash != 4 { abort }
    map ::= unwrap_or_abort(.value = HashMap#(.key: Key, .value: Int32)())
    unwrap_or_abort(.value = put($&map, .key = key, .value = 42))
    match get(&map, .key = &key).result {
        ..none { abort }
        ..some item { if item.value != 42 { abort } }
    }
    custom ::= unwrap_or_abort(
        .value = HashMap#(.key: Key, .value: Int32)(.policy = CollisionPolicy())
    )
    unwrap_or_abort(.value = put($&custom, .key = key, .value = 43))
    match get(&custom, .key = &key).result {
        ..none { abort }
        ..some item { if item.value != 43 { abort } }
    }
}
