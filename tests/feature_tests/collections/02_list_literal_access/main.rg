main () -> (.status_code: Int32) := {
    first : Int32 = (40, 50)[0]
    if first != 40 {
        status_code = 2
        return
    }

    second : Int32 = (0, 7, 14)[1]
    if second != 7 {
        status_code = 3
        return
    }

    status_code = 0
}
