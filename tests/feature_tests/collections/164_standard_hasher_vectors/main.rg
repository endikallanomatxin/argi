-- Raw FNV-1a-64 known answers, independently of key encoding and map probing.
check(.bytes: ArrayView#(UInt8), .expected: UInt64) -> () := {
    hasher ::= StandardHasher()
    Hasher#(StandardHasher).write_bytes($&hasher, .bytes = bytes)
    #if target_pointer_bits(64) {
        if Hasher#(StandardHasher).finish(&hasher).hash != [expected | convert#(
                .to : UIntNative
            )(_)] { abort }
    }
}

main() -> () := {
    bytes_0: [0]UInt8 = ()
    check(.bytes = view(&bytes_0), .expected = 14695981039346656037)
    bytes_1: [1]UInt8 = (97)
    check(.bytes = view(&bytes_1), .expected = 12638187200555641996)
    bytes_2: [6]UInt8 = (102, 111, 111, 98, 97, 114)
    check(.bytes = view(&bytes_2), .expected = 9625390261332436968)
    bytes_3: [5]UInt8 = (0, 255, 128, 0, 1)
    check(.bytes = view(&bytes_3), .expected = 15957228348348010579)
    bytes_4 ::= zeroed#(.t: [256]UInt8)()
    index :: UIntNative = 0
    while index < 256 {
        bytes_4[index] = unwrap_or_abort(.value = [index | convert#(.to: UInt8)(_)])
        index = index + 1
    }
    check(.bytes = view(&bytes_4), .expected = 4774620800949106213)
    first: [3]UInt8 = (102, 111, 111)
    second: [3]UInt8 = (98, 97, 114)
    split ::= StandardHasher()
    Hasher#(StandardHasher).write_bytes($&split, .bytes = view(&first))
    Hasher#(StandardHasher).write_bytes($&split, .bytes = view(&second))
    #if target_pointer_bits(64) {
        expected: UIntNative = 9625390261332436968
        if Hasher#(StandardHasher).finish(&split).hash != expected { abort }
    }
}
