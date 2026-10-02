accept_ints(.values: [2]Int32) -> (.value: Int32) := { value = values[1] }
accept_floats(.values: [2]Float32) -> (.value: Float32) := { value = values[1] }
accept_bytes(.values: [2]UInt8) -> (.value: UInt8) := { value = values[1] }
accept_nested(.values: [2][2]Int64) -> (.value: Int64) := { value = values[1][1] }
make_byte() -> (.value: UInt8 = 7) := {}

main() -> (.status_code: Int32 = 0) := {
    ints := (1, 2)
    floats := (1.0, 2.0)
    flags := (true, false)
    words := ("first", "second")
    byte : UInt8 = 9
    bytes := (make_byte(), byte)
    if accept_ints(ints) != 2 { status_code = 1 }
    if accept_floats(floats) != 2.0 { status_code = 2 }
    if flags[0] != true or flags[1] != false { status_code = 3 }
    if words[1] != "second" { status_code = 4 }
    if accept_bytes(bytes) != 9 { status_code = 5 }
    if accept_nested(((1, 2), (3, 4))) != 4 { status_code = 6 }
    wide : [2][2]Int64 = ((1, 2), (3, 4))
    if accept_nested(wide) != 4 { status_code = 7 }
    row := (5, 6)
    rows := (row, row)
    if rows[1][0] != 5 { status_code = 8 }
    empty : [0]Int32 = ()
}
