-- Bounded byte copies are language operations and need no foreign-call
-- authority. Source and destination must not overlap, as with memcpy.
memcpy_bytes := #(.Source: Type) (.dst: MutableArrayView#(.t: UInt8), .src: Source) -> () {
    assume error_tracer ::= NoopErrorTracer() | to_virtual#(.contract: ErrorTracer)($&_) | $&_
    count ::= length(&dst).count

    if count > length(&src).count { abort }
    target :: MutableArrayView#(.t: UInt8) = dst
    index :: UIntNative = 0

    while index < count {
        byte ::= unwrap_or_abort(.value = get(&src, .index = index))
        unwrap_or_abort(.value = set#(.t: UInt8)($&target, .index = index, .value = byte))
        index = index + 1
    }
}
