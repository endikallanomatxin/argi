main () -> (.status_code: Int32) := {
    three := length(.value=(10, 20, 30))
    if three != 3 {
        status_code = 1
        return
    }

    status_code = 0
}
