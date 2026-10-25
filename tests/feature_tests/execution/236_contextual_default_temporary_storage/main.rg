main() -> (.status_code: Int32) := {
    assume error_tracer ::= $&noop_error_tracer
    first :: (
        .marker : Int32
        .bytes  : MutableArrayView#(.t: UInt8) = view($&zeroed#(.t: [2]UInt8)())
    ) = (.marker = 1)
    second :: (
        .marker : Int32
        .bytes  : MutableArrayView#(.t: UInt8) = view($&zeroed#(.t: [2]UInt8)())
    ) = (.marker = 2)
    left ::= unwrap_or_abort(.value = get_mutable_reference(.self = $&first.bytes, .index = 0))
    right ::= unwrap_or_abort(
        .value = get_mutable_reference(.self = $&second.bytes, .index = 0)
    )
    left&= 20
    right&= 22
    if left&+ right&!= 42 { abort }
    status_code = 42
}
