Tracked: Type = (.id: Int32)

key_drops :: Int32 = 0
value_drops :: Int32 = 0
policy_drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { value_drops = value_drops + 1 }

Key: Type = (.id: Int32)

Key deinit(.self: $&Key) -> () := { key_drops = key_drops + 1 }

Policy: Type = ()

Policy implements BorrowedHashPolicy#(.key: Key)

Policy deinit(.self: $&Policy) -> () := { policy_drops = policy_drops + 1 }

hash(.self: &Policy, .key: &Key) -> (.hash: UIntNative) := { hash = 7 }

eql(.self: &Policy, .left: &Key, .right: &Key) -> (.ok: Bool) := { ok = left&.id == right&.id }

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: Key, .value: Tracked, .policy: Policy)(
        .policy    = Policy()
        .allocator = allocator
    )!
    index :: Int32 = 0
    while index < 30 {
        put(
            .self      = $&map
            .key       = Key(.id = index)
            .value     = Tracked(.id = index * 3)
            .allocator = allocator
        )!
        index = index + 1
    }
    if key_drops != 0 or value_drops != 0 or policy_drops != 0 { abort }
    for entry in map { if entry.value&.id != entry.key&.id * 3 { abort } }
    put(.self = $&map, .key = Key(.id = 2), .value = Tracked(.id = 99), .allocator = allocator)!
    if key_drops != 1 or value_drops != 1 { abort }
    query ::= Key(.id = 2)
    match get_ro_ref(.self = &map, .key = &query).result {
        ..none { abort }
        ..some payload { if payload.value&.id != 99 { abort } }
    }
    if remove(.self = $&map, .key = &query, .allocator = allocator).removed == false { abort }
    if remove(.self = $&map, .key = &query, .allocator = allocator).removed { abort }
    if key_drops != 2 or value_drops != 2 { abort }
    query.id = 3
    extracted ::= extract(.self = $&map, .key = &query).result
    if key_drops != 2 or value_drops != 2 or length(.self = &map).count != 28 { abort }
    deinit(.self = $&map, .allocator = allocator)
    if key_drops != 30 or value_drops != 30 or policy_drops != 1 { abort }
    match extracted {
        ..none { abort }
        ..some ~payload {
            entry ::= ~payload.value
            if entry.key.id != 3 or entry.value.id != 9 { abort }
            deinit(.self = $&entry.key)
            deinit(.self = $&entry.value)
        }
    }
    if key_drops != 31 or value_drops != 31 { abort }
    set ::= OwnedHashSet#(.key: Key, .policy: Policy)(.policy = Policy(), .allocator = allocator)!
    if insert(.self = $&set, .key = Key(.id = 5), .allocator = allocator)! == false { abort }
    if insert(.self = $&set, .key = Key(.id = 5), .allocator = allocator)! { abort }
    if key_drops != 32 { abort }
    iterator ::= to_ro_pointer_iterator(.value = &set).iterator
    if has_next(.self = &iterator).ok == false { abort }
    if next(.self = $&iterator).value&.id != 5 { abort }
    if has_next(.self = &iterator).ok { abort }
    query.id = 5
    taken ::= extract(.self = $&set, .key = &query).result
    deinit(.self = $&set, .allocator = allocator)
    if policy_drops != 2 or key_drops != 32 { abort }
    match taken {
        ..none { abort }
        ..some ~payload {
            key ::= ~payload.value
            if key.id != 5 { abort }
            deinit(.self = $&key)
        }
    }
    if key_drops != 33 { abort }
}
