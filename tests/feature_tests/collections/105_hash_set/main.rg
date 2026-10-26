CollisionPolicy := (.marker: Int32 = 0)

implement ImplicitlyCopyable<CollisionPolicy> ()

implement HashPolicy<CollisionPolicy, Int32> (
    .Query : Type = &Int32
    .query = (.self: &CollisionPolicy, .key: &Int32) -> (.query: Query) { query = key }

    .hash  = (.self: &CollisionPolicy, .key: &Int32) -> (.hash: UIntNative) { hash = 7 }
    .equal = (.self: &CollisionPolicy, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = [left&== right&]
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator ::= system.page_allocator
    set ::= unwrap_or_abort(
        .value = HashSet<.key: Int32, .policy: CollisionPolicy>(
            .policy = CollisionPolicy(), .allocator = allocator
        )
    )
    index :: Int32 = 0
    while index < 40 {
        if [
            unwrap_or_abort(
                .value = insert(.self = $&set, .key = index, .allocator = allocator)
            )
            == false
        ] { abort }
        if unwrap_or_abort(.value = insert(.self = $&set, .key = index, .allocator = allocator)) {
            abort
        }
        index = index + 1
    }
    if length(.self = &set).count != 40 { abort }
    index = 0
    while index < 40 {
        if contains(.self = &set, .key = &index).ok == false { abort }
        if remove(.self = $&set, .key = &index, .allocator = allocator).removed == false {
            abort
        }
        if contains(.self = &set, .key = &index).ok { abort }
        index = index + 1
    }
    if remove(.self = $&set, .key = &0, .allocator = allocator).removed { abort }
    if length(.self = &set).count != 0 { abort }
    deinit(.self = $&set)
    text ::= unwrap_or_abort(
        .value = HashSet<.key: StringView, .policy: StandardHashPolicy>(
            .policy = StandardHashPolicy(), .allocator = allocator
        )
    )
    bytes: [3]UInt8 = (97, 0, 98)
    same: [3]UInt8 = (97, 0, 98)
    left_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&bytes), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    left ::= view(&left_storage)
    right_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&same), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    right ::= view(&right_storage)
    if [
        unwrap_or_abort(.value = insert(.self = $&text, .key = left, .allocator = allocator))
        == false
    ] { abort }
    if unwrap_or_abort(.value = insert(.self = $&text, .key = right, .allocator = allocator)) {
        abort
    }
    if contains(.self = &text, .key = right).ok == false { abort }
    if length(.self = &text).count != 1 { abort }
    deinit(.self = $&text)
}
