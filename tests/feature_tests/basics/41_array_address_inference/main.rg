main() -> (.status_code: Int32 = 0) := {
    first := $&(1,2)
    first&[0] = 9
    if first&[0] != 9 or first&[1] != 2 { status_code = 1 }
}
