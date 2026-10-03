widen#(.t: Type)(.value: t) -> (.result: Int64) := {
    result = Int64(.value = value)
}
evaluations :: Int32 = 0
next_value() -> (.value: Int64) := {
    evaluations = evaluations + 1
    value = 127
}
checked#(.t: Type)(.value: t) -> (.result: Errable#(.t: Int8, .reasons: (..out_of_range))) := {
    result = Int8(.value = value)
}
narrow(.value: Int64) -> (.result: Errable#(.t: Int8, .reasons: (..out_of_range))) := {
    result = Int8(.value = value)
}
main() -> (.status_code: Int32 = 0) := {
    small : Int8 = -128
    wide : Int64 = Int64(.value = small)
    if wide != -128 or widen(.value = small) != -128 { status_code = 1 }
    byte : UInt8 = 255
    extended : Int16 = Int16(.value = byte)
    if extended != 255 { status_code = 2 }
    exact : Int64 = -128
    if unwrap_or_abort(.value = narrow(.value = exact)) != -128 { status_code = 3 }
    high : Int64 = 128
    if is(.value = narrow(.value = high), .variant = ..error) == false { status_code = 4 }
    low : Int64 = -129
    if is(.value = narrow(.value = low), .variant = ..error) == false { status_code = 5 }
    negative : Int32 = -1
    failed ::= UInt64(.value = negative)
    match failed {
        ..ok _ { status_code = 6 }
        ..error payload { if is(.value = payload.reason, .variant = ..out_of_range) == false { status_code = 7 } }
    }
    maximum : UInt64 = 18446744073709551615
    if is(.value = Int64(.value = maximum), .variant = ..error) == false { status_code = 8 }
    signed_maximum : UInt64 = 9223372036854775807
    if unwrap_or_abort(.value = Int64(.value = signed_maximum)) != 9223372036854775807 { status_code = 9 }
    native : UIntNative = UIntNative(.value = byte)
    if native != 255 { status_code = 10 }
    if unwrap_or_abort(.value = Int8(.value = next_value())) != 127 or evaluations != 1 { status_code = 11 }
    if unwrap_or_abort(.value = checked(.value = exact)) != -128 { status_code = 12 }
    c_small : CShort = -7
    c_wide : CLongLong = CLongLong(.value = c_small)
    if c_wide != -7 { status_code = 13 }
}
