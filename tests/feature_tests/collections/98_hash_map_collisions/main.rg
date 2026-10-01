CollisionPolicy : Type = (.marker: Int32 = 0)
CollisionPolicy implements ImplicitlyCopyable
CollisionPolicy implements HashPolicy#(.key: Int32)
hash(.self: &CollisionPolicy, .key: Int32) -> (.hash: UIntNative) := { hash = 7 }
eql(.self: &CollisionPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left == right }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: Int32, .value: Int32, .policy: CollisionPolicy)(.policy = CollisionPolicy(), .allocator = allocator))
    index :: Int32 = 0
    while index < 4 {
        unwrap_or_abort(.value = put#(.key: Int32, .value: Int32, .policy: CollisionPolicy)(.self = $&map, .key = index, .value = index, .allocator = allocator))
        index = index + 1
    }
    if remove(.self = $&map, .key = 0, .allocator = allocator).removed == false { abort }
    if remove(.self = $&map, .key = 2, .allocator = allocator).removed == false { abort }
    unwrap_or_abort(.value = put#(.key: Int32, .value: Int32, .policy: CollisionPolicy)(.self = $&map, .key = 3, .value = 99, .allocator = allocator))
    if length(.self = &map).count != 2 { abort }
    index = 4
    while index < 100 {
        unwrap_or_abort(.value = put#(.key: Int32, .value: Int32, .policy: CollisionPolicy)(.self = $&map, .key = index, .value = index, .allocator = allocator))
        if contains(.self = &map, .key = index).ok == false { abort }
        if remove(.self = $&map, .key = index, .allocator = allocator).removed == false { abort }
        index = index + 1
    }
    if contains(.self = &map, .key = 100).ok { abort }
    match get(.self = &map, .key = 3).result {
        ..none { abort }
        ..some entry { if entry.value != 99 { abort } }
    }
    if length(.self = &map).count != 2 or capacity(.self = &map).count != 8 { abort }
    deinit(.self = $&map, .allocator = allocator)
}
