store_byte#(.t: Type)(.marker: t, .bytes: $&[4]UInt8) -> () := {
    bytes&[0] = 45
    bytes&[2] = 255
}
main() -> (.status_code: Int32 = 0) := {
    bytes: [4]UInt8 = (11, 22, 33, 44)
    store_byte(.marker = 1, .bytes = $&bytes)
    if bytes[0] != 45 or bytes[1] != 22 or bytes[2] != 255 or bytes[3] != 44 { abort }
    bytes[1] = 128
    if bytes[0] != 45 or bytes[1] != 128 or bytes[2] != 255 or bytes[3] != 44 { abort }
}
