Pair: CStruct = (.first: UInt64, .second: UInt64)
shift := (.base: $&UInt64) -> (.result: $&UInt64) {
    result = trusted_mutable_reference_offset#(.t: UInt64)(.base = base, .elements = 1).reference
}
main := () -> () {
    values :: Pair = (7, 11)
    first ::= $&values.first
    second ::= shift(.base = first)
    second& = 17
    first& = 9
    if values.first != 9 or values.second != 17 { abort }
    readonly ::= trusted_reference_offset#(.t: UInt64)(.base = &values.first, .elements = 1).reference
    if readonly& != 17 { abort }
    whole ::= trusted_mutable_reinterpret_reference#(.from: UInt64, .to: Pair)(.base = first).reference
    whole&.second = 23
    if values.second != 23 { abort }
}
