main () -> (.status_code: Int32) := {
    tiny : Int8 = -128
    signed : Int32 = -42

    if tiny != -128 {
        status_code = 1
        return
    }

    if signed != -42 {
        status_code = 2
        return
    }

    status_code = 0
}
