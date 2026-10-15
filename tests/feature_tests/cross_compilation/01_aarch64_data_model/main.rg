-- Linux ARM64 has unsigned plain C char, unlike Linux x86_64.
Packet : CStruct = (.value: CDouble, .count: CLong, .character: CChar)
character(.value: CChar) -> (.result: CChar) : CFunction(.export = true, .symbol = "argi_cross_character") := {
    result = value
}
packet(.value: Packet) -> (.result: Packet) : CFunction(.export = true, .symbol = "argi_cross_packet") := {
    result = value
}
empty_character#(.unused: Type)() -> (.result: CChar) := {
    result = zeroed#(.t: CChar)()
}
main() -> (.status_code: Int32 = 0) := {
    value : CChar = 255
    empty : CChar = empty_character#(.unused: Int32)()
}
