CollisionPolicy: Type = ()

CollisionPolicy implements ImplicitlyCopyable
CollisionPolicy implements HashPolicy#(.key: Int32)

hash(.self: &CollisionPolicy, .key: Int32) -> (.hash: UIntNative) := { hash = 7 }

eql(.self: &CollisionPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left == right }

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: CollisionPolicy)(
        .policy    = CollisionPolicy()
        .allocator = allocator
    )!
    index :: Int32 = 0
    while index < 4 {
        put(.self = $&map, .key = index, .value = index + 10, .allocator = allocator)!
        index = index + 1
    }
    remove(.self = $&map, .key = 0, .allocator = allocator)
    remove(.self = $&map, .key = 2, .allocator = allocator)
    put(.self = $&map, .key = 3, .value = 99, .allocator = allocator)!
    keys :: Int32 = 0
    values :: Int32 = 0
    count :: UIntNative = 0
    iterator ::= to_iterator(.value = &map).iterator
    while has_next(.self = &iterator).ok {
        if has_next(.self = &iterator).ok == false { abort }
        entry ::= next(.self = $&iterator).value
        keys = keys + entry.key
        values = values + entry.value
        count = count + 1
    }
    if count != 2 or keys != 4 or values != 110 { abort }
    if has_next(.self = &iterator).ok { abort }
    put(.self = $&map, .key = 5, .value = 15, .allocator = allocator)!
    count = 0
    for entry in map { count = count + 1 }
    if count != 3 { abort }
}
