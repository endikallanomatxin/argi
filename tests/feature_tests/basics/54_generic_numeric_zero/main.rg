zeros#(.t: Type)(.value: t) -> (.signed: Int64, .unsigned: UInt64, .float: Float64, .native: UIntNative, .boolean: Bool) := {
    signed = Int64()
    unsigned = UInt64()
    float = Float64()
    native = UIntNative()
    boolean = Bool()
    small_signed ::= Int8()
    small_unsigned ::= UInt8()
    half ::= Float16()
    medium ::= Float32()
    half_zero : Float16 = 0.0
    if small_signed != 0 or small_unsigned != 0 or half != half_zero or medium != 0.0 { signed = 1 }
}

main() -> (.status_code: Int32 = 0) := {
    result ::= zeros(.value = 1)
    float_zero : Float64 = 0.0
    if result.signed != 0 or result.unsigned != 0 or result.float != float_zero or result.native != 0 or result.boolean { status_code = 1 }
}
