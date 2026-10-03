choose(.flag: Bool) -> (.bytes: [65536]UInt8) := {
    bytes = zeroed#(.t: [65536]UInt8)()
    if flag { bytes[0] = 9 } else { bytes[65535] = 7 }
}
main() -> (.status_code: Int32 = 0) := {
    left ::= choose(.flag = true)
    right ::= choose(.flag = false)
    if left[0] != 9 or left[65535] != 0 { abort }
    if right[0] != 0 or right[65535] != 7 { abort }
}
