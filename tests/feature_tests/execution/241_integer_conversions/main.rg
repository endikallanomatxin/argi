main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    negative: Int8 = -42
    wide ::= negative | convert#(.to: Int64)(_)
    if wide != -42 { abort }
    positive: UInt8 = 255
    unsigned_wide ::= positive | convert#(.to: UInt64)(_)
    if unsigned_wide != 255 { abort }
    signed_wide ::= positive | convert#(.to: Int32)(_)
    if signed_wide != 255 { abort }
    small ::= unwrap_or_abort(.value = [wide | convert#(.to: Int8)(_)])
    if small != -42 { abort }
    too_large: Int64 = 128
    match [too_large | convert#(.to: Int8)(_)] {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..out_of_range { abort } }
    }
    match [negative | convert#(.to: UInt64)(_)] {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..out_of_range { abort } }
    }
    largest: UInt64 = 18446744073709551615
    match [largest | convert#(.to: Int64)(_)] {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..out_of_range { abort } }
    }
    native ::= positive | convert#(.to: UIntNative)(_)
    if native != 255 { abort }
    status_code = #run () -> (.result: Int32) {
        byte: Int8 = 42
        result = byte | convert#(.to: Int32)(_)
    }
}
