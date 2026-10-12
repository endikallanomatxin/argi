-- Bounded byte copies are language operations and need no foreign-call
-- authority. Source and destination must not overlap, as with memcpy.
memcpy_bytes(
        .dst : ArrayView#(.t: UInt8),
        .src : ArrayView#(.t: UInt8),
    ) -> () := {
    count ::= length(&dst).count

    if count > length(&src).count { abort }
    target :: ArrayView#(.t: UInt8) = dst
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get(&src, .index = index))
        unwrap_or_abort(.value = set#(.t: UInt8)($&target, .index = index, .value = byte))
        index = index + 1
    }
}

memcpy_bytes(
        .dst : ArrayView#(.t: UInt8),
        .src : ArrayViewRO#(.t: UInt8),
    ) -> () := {
    count ::= length(&dst).count

    if count > length(&src).count { abort }
    target :: ArrayView#(.t: UInt8) = dst
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get(&src, .index = index))
        unwrap_or_abort(.value = set#(.t: UInt8)($&target, .index = index, .value = byte))
        index = index + 1
    }
}
