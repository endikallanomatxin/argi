store_byte#(.t: Type)(.marker: t, .bytes: $&[2]UInt8) -> () := {
    bytes&[0] = 256
}
main() -> (.status_code: Int32 = 0) := {
    bytes: [2]UInt8 = (0, 0)
    store_byte(.marker = 1, .bytes = $&bytes)
}
