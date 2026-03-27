main() -> (.status_code: Int32) := {
    a := true
    b := false

    if a {
        if b {
            status_code = 1
            return
        }
    } else {
        status_code = 2
        return
    }

    status_code = 0
}
