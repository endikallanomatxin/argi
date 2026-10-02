main() -> (.status_code: Int32 = 0) := {
    first : [2][2]Int32 = ((1,2), (3,4))
    if first[0][0] != 1 or first[1][1] != 4 { status_code = 1 }
}
