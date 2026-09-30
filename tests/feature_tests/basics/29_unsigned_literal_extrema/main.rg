identity#(.t: Type)(.value: t) -> (.result: t) := { result = value }
maximum#(.t: Type)() -> (.result: t) := { result = 18446744073709551615 }
main() -> (.status_code: Int32 = 0) := {
    byte : UInt8 = 255
    short : UInt16 = 65535
    word : UInt32 = 4294967295
    signed_min : Int64 = -9223372036854775808
    signed_max : Int64 = 9223372036854775807
    unsigned : UInt64 = 18446744073709551615
    native : UIntNative = 18446744073709551615
    hexadecimal : UInt64 = 0xffffffffffffffff
    binary : UInt64 = 0b1111111111111111111111111111111111111111111111111111111111111111
    octal : UInt64 = 0o1777777777777777777777
    forwarded ::= identity#(.t: UInt64)(.value = 18446744073709551615).result
    generic ::= maximum#(.t: UInt64)().result
    if byte != 255 or short != 65535 or word != 4294967295 { status_code = 1 }
    if signed_min != -9223372036854775808 or signed_max != 9223372036854775807 { status_code = 2 }
    if unsigned != hexadecimal or unsigned != binary or unsigned != octal { status_code = 3 }
    if unsigned != forwarded or unsigned != generic { status_code = 4 }
    if native - 18446744073709551614 != 1 { status_code = 5 }
}
