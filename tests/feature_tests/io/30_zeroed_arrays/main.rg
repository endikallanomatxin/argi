main() -> (.status_code: Int32 = 0) := {
    bytes ::= zeroed#(.t: [4096]UInt8)()
    i :: UIntNative = 0
    while i < 4096 {
        if bytes[i] != 0 { status_code = 1 return }
        i = i + 1
    }
    nested ::= zeroed#(.t: [2][3]Int32)()
    if nested[1][2] != 0 { status_code = 2 return }
    number ::= zeroed#(.t: Float32)()
    if number != 0.0 { status_code = 3 return }
    empty ::= zeroed#(.t: [0]UInt8)()
    if length(.value = empty) != 0 { status_code = 4 }
}
