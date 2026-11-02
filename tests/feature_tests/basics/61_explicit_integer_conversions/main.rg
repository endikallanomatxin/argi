widen := #(.t: Type) (.value: t) -> (.result: Int64) {

    result = value | convert#(.to: Int64)(_)
}

evaluations :: Int32 = 0

next_value := () -> (.value: Int64) {
    evaluations = evaluations + 1
    value = 127
}

checked := #(.t: Type) (.value: t) -> (.result: Errable#(.t: Int8, .reasons: (..out_of_range))) {

    result = value | convert#(.to: Int8)(_)
}

narrow := (.value: Int64) -> (.result: Errable#(.t: Int8, .reasons: (..out_of_range))) {

    result = value | convert#(.to: Int8)(_)
}

main := () -> (.status_code: Int32 = 0) {

    small: Int8 = -128
    wide: Int64 = small | convert#(.to: Int64)(_)
    if wide != -128 or widen(.value = small) != -128 { status_code = 1 }
    byte: UInt8 = 255
    extended: Int16 = byte | convert#(.to: Int16)(_)
    if extended != 255 { status_code = 2 }
    exact: Int64 = -128
    if unwrap_or_abort(.value = narrow(.value = exact)) != -128 { status_code = 3 }
    high: Int64 = 128
    if is(.value = narrow(.value = high), .variant = ..error) == false { status_code = 4 }
    low: Int64 = -129
    if is(.value = narrow(.value = low), .variant = ..error) == false { status_code = 5 }
    negative: Int32 = -1
    failed ::= negative | convert#(.to: UInt64)(_)
    match failed {
        ..ok _ { status_code = 6 }
        ..error payload {
            if is(.value = payload.reason, .variant = ..out_of_range) == false {
                status_code = 7
            }
        }
    }
    maximum: UInt64 = 18446744073709551615
    if is(.value = maximum | convert#(.to: Int64)(_), .variant = ..error) == false {
        status_code = 8
    }
    signed_maximum: UInt64 = 9223372036854775807
    if [
        unwrap_or_abort(.value = signed_maximum | convert#(.to: Int64)(_))
        != 9223372036854775807
    ] { status_code = 9 }
    native: UIntNative = byte | convert#(.to: UIntNative)(_)
    if native != 255 { status_code = 10 }
    if [
        unwrap_or_abort(.value = next_value() | convert#(.to: Int8)(_)) != 127
        or evaluations != 1
    ] { status_code = 11 }
    if unwrap_or_abort(.value = checked(.value = exact)) != -128 { status_code = 12 }
    c_small: CShort = -7
    c_wide: CLongLong = c_small | convert#(.to: CLongLong)(_)
    if c_wide != -7 { status_code = 13 }
}
