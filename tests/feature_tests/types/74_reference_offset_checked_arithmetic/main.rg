main() -> (.status_code: Int32) := {
    values :: Array#(.n = 3, .t: UIntNative) = (11, 22, 33)
    first ::= trusted_mutable_reinterpret_reference#(.from: Array#(.n = 3, .t: UIntNative), .to: UIntNative)(.base = $&values).reference
    second ::= trusted_mutable_reference_offset#(.t: UIntNative)(.base = first, .elements = 1).reference
    second& = 44
    readonly ::= read_reference#(.t: UIntNative)(.base = first).reference
    last ::= trusted_reference_offset#(.t: UIntNative)(.base = readonly, .elements = 2).reference
    zero ::= trusted_reference_offset#(.t: UIntNative)(.base = readonly, .elements = 0).reference
    status_code = 0
    if last& != 33 or second& != 44 or zero& != 11 { status_code = 1 }
}
