main() -> (.status_code: Int32 = 0) := {
    small :: UInt8 = 0
    signed :: Int64 = 0
    wide :: UInt64 = 0
    native :: UIntNative = 0
    if integer_limits(.value = small).maximum != 255 { abort }
    if integer_limits(.value = signed).minimum != -9223372036854775808 { abort }
    if integer_limits(.value = wide).maximum != 18446744073709551615 { abort }
    maximum ::= integer_limits(.value = native).maximum
    if [
        unwrap_or_abort(.value = round_up#(.t: UIntNative)(.value = maximum, .multiple = 1))
        != maximum
    ] { abort }
    match round_up#(.t: UIntNative)(.value = maximum, .multiple = 2) {
        ..ok _ { abort } ..error _ {}
    }
    match round_down#(.t: UInt8)(.value = 0, .multiple = 0) { ..ok _ { abort } ..error _ {} }
    match round_up#(.t: UInt8)(.value = 0, .multiple = 0) { ..ok _ { abort } ..error _ {} }
    if unwrap_or_abort(.value = round_up#(.t: UInt8)(.value = 253, .multiple = 3)) != 255 { abort }
    if unwrap_or_abort(.value = round_down#(.t: UInt16)(.value = 100, .multiple = 7)) != 98 {
        abort
    }
    byte :: UInt8 = 0
    total :: UIntNative = 0
    powers :: UIntNative = 0
    while true {
        reversed ::= reverse_bits#(.t: UInt8)(.value = byte).result
        if reverse_bits#(.t: UInt8)(.value = reversed).result != byte { abort }
        ones ::= count_ones#(.t: UInt8)(.value = byte).count
        total = total + ones
        if is_power_of_two#(.t: UInt8)(.value = byte).ok { powers = powers + 1 }
        if count_ones#(.t: UInt8)(.value = reversed).count != ones { abort }
        if byte != 0 {
            if [
                [
                    count_leading_zeros#(.t: UInt8)(.value = byte).count
                    + bit_length#(.t: UInt8)(.value = byte).count
                ]
                != 8
            ] { abort }
            if [
                count_trailing_zeros#(.t: UInt8)(.value = reversed).count
                != count_leading_zeros#(.t: UInt8)(.value = byte).count
            ] { abort }
        }
        if byte == 255 { break }
        byte = byte + 1
    }
    if total != 1024 or powers != 8 { abort }
    if count_trailing_zeros#(.t: UInt64)(.value = 0).count != 64 { abort }
    if count_leading_zeros#(.t: UInt32)(.value = 0).count != 32 { abort }
    if reverse_bits#(.t: UInt16)(.value = 1).result != 32768 { abort }
    if reverse_bits#(.t: UInt64)(.value = 1).result != 9223372036854775808 { abort }
    if bit_length#(.t: UIntNative)(.value = maximum).count != size_of(.type = UIntNative) * 8 {
        abort
    }
}
