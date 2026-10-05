-- Bounded byte copies are language operations and need no foreign-call
-- authority. Source and destination must not overlap, as with memcpy.
memcpy_bytes(
        .dst : ArrayView#(.t: UInt8),
        .src : ArrayView#(.t: UInt8),
    ) -> () := {
    count ::= length#(.t: UInt8)(.self = &dst).count

    if count > length#(.t: UInt8)(.self = &src).count { abort }
    target :: ArrayView#(.t: UInt8) = dst
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get#(.t: UInt8)(.self = &src, .index = index))
        unwrap_or_abort(.value = set#(.t: UInt8)(.self = $&target, .index = index, .value = byte))
        index = index + 1
    }
}

memcpy_bytes(
        .dst : ArrayView#(.t: UInt8),
        .src : ArrayViewRO#(.t: UInt8),
    ) -> () := {
    count ::= length#(.t: UInt8)(.self = &dst).count

    if count > length#(.t: UInt8)(.self = &src).count { abort }
    target :: ArrayView#(.t: UInt8) = dst
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get#(.t: UInt8)(.self = &src, .index = index))
        unwrap_or_abort(.value = set#(.t: UInt8)(.self = $&target, .index = index, .value = byte))
        index = index + 1
    }
}
