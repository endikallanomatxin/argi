expect_error#(.t: Type: Int)(
    .value: Errable#(.t: t, .reasons: (..invalid_base, ..invalid_input, ..out_of_range)),
    .reason: (..invalid_base, ..invalid_input, ..out_of_range),
) -> () := {
    match value {
        ..ok _ { abort }
        ..error error { if error.reason != reason { abort } }
    }
}
main() -> (.status_code: Int32 = 0) := {
    if unwrap_or_abort(.value = parse_uint8(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint8(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint8(.text = "255")).result != 255 { abort }
    expect_error#(.t: UInt8)(.value = parse_uint8(.text = "256").result, .reason = ..out_of_range)
    expect_error#(.t: UInt8)(.value = parse_uint8(.text = "-1").result, .reason = ..invalid_input)
    if unwrap_or_abort(.value = parse_uint16(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint16(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint16(.text = "65535")).result != 65535 { abort }
    expect_error#(.t: UInt16)(.value = parse_uint16(.text = "65536").result, .reason = ..out_of_range)
    expect_error#(.t: UInt16)(.value = parse_uint16(.text = "-1").result, .reason = ..invalid_input)
    if unwrap_or_abort(.value = parse_uint32(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint32(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint32(.text = "4294967295")).result != 4294967295 { abort }
    expect_error#(.t: UInt32)(.value = parse_uint32(.text = "4294967296").result, .reason = ..out_of_range)
    expect_error#(.t: UInt32)(.value = parse_uint32(.text = "-1").result, .reason = ..invalid_input)
    if unwrap_or_abort(.value = parse_uint64(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint64(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint64(.text = "18446744073709551615")).result != 18446744073709551615 { abort }
    expect_error#(.t: UInt64)(.value = parse_uint64(.text = "18446744073709551616").result, .reason = ..out_of_range)
    expect_error#(.t: UInt64)(.value = parse_uint64(.text = "-1").result, .reason = ..invalid_input)
    if unwrap_or_abort(.value = parse_int8(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_int8(.text = "-128")).result != -128 { abort }
    if unwrap_or_abort(.value = parse_int8(.text = "127")).result != 127 { abort }
    expect_error#(.t: Int8)(.value = parse_int8(.text = "128").result, .reason = ..out_of_range)
    expect_error#(.t: Int8)(.value = parse_int8(.text = "-129").result, .reason = ..out_of_range)
    if unwrap_or_abort(.value = parse_int16(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_int16(.text = "-32768")).result != -32768 { abort }
    if unwrap_or_abort(.value = parse_int16(.text = "32767")).result != 32767 { abort }
    expect_error#(.t: Int16)(.value = parse_int16(.text = "32768").result, .reason = ..out_of_range)
    expect_error#(.t: Int16)(.value = parse_int16(.text = "-32769").result, .reason = ..out_of_range)
    if unwrap_or_abort(.value = parse_int32(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_int32(.text = "-2147483648")).result != -2147483648 { abort }
    if unwrap_or_abort(.value = parse_int32(.text = "2147483647")).result != 2147483647 { abort }
    expect_error#(.t: Int32)(.value = parse_int32(.text = "2147483648").result, .reason = ..out_of_range)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "-2147483649").result, .reason = ..out_of_range)
    if unwrap_or_abort(.value = parse_int64(.text = "0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_int64(.text = "-9223372036854775808")).result != -9223372036854775808 { abort }
    if unwrap_or_abort(.value = parse_int64(.text = "9223372036854775807")).result != 9223372036854775807 { abort }
    expect_error#(.t: Int64)(.value = parse_int64(.text = "9223372036854775808").result, .reason = ..out_of_range)
    expect_error#(.t: Int64)(.value = parse_int64(.text = "-9223372036854775809").result, .reason = ..out_of_range)
    if unwrap_or_abort(.value = parse_uint64(.text = "ffffffffffffffff", .base = 16)).result != 18446744073709551615 { abort }
    if unwrap_or_abort(.value = parse_int64(.text = "-8000000000000000", .base = 16)).result != -9223372036854775808 { abort }
    if unwrap_or_abort(.value = parse_int32(.text = "+00042")).result != 42 { abort }
    if unwrap_or_abort(.value = parse_int8(.text = "-0")).result != 0 { abort }
    if unwrap_or_abort(.value = parse_uint8(.text = "FF", .base = 16)).result != 255 { abort }
    if unwrap_or_abort(.value = parse_uint8(.text = "11111111", .base = 2)).result != 255 { abort }
    if unwrap_or_abort(.value = parse_uint8(.text = "Z", .base = 36)).result != 35 { abort }
    expect_error#(.t: Int32)(.value = parse_int32(.text = "").result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "+").result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "-").result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = " 1").result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "1 ").result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "1_0").result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "0xff", .base = 16).result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "2", .base = 2).result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "z", .base = 35).result, .reason = ..invalid_input)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "1", .base = 1).result, .reason = ..invalid_base)
    expect_error#(.t: Int32)(.value = parse_int32(.text = "1", .base = 37).result, .reason = ..invalid_base)
    if unwrap_or_abort(.value = parse_int8(.text = "3j", .base = 36)).result != 127 { abort }
    if unwrap_or_abort(.value = parse_int8(.text = "-3k", .base = 36)).result != -128 { abort }
    expect_error#(.t: Int8)(.value = parse_int8(.text = "3k", .base = 36).result, .reason = ..out_of_range)
    expect_error#(.t: Int8)(.value = parse_int8(.text = "-3l", .base = 36).result, .reason = ..out_of_range)
    if unwrap_or_abort(.value = parse_uint64(.text = "1111111111111111111111111111111111111111111111111111111111111111", .base = 2)).result != 18446744073709551615 { abort }
    expect_error#(.t: UInt64)(.value = parse_uint64(.text = "10000000000000000000000000000000000000000000000000000000000000000", .base = 2).result, .reason = ..out_of_range)
    expect_error#(.t: UInt8)(.value = parse_uint8(.text = "-0").result, .reason = ..invalid_input)
    bytes : [3]UInt8 = (49, 0, 50)
    binary :: StringView = (.data = &bytes[0], .length = 3)
    expect_error#(.t: UInt32)(.value = parse_uint32(.text = binary).result, .reason = ..invalid_input)
}
