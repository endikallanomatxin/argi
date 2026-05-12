foo(.x: Int32) -> (.ok: Bool) := {
    if bar(.x = x).ok {
        ok = true
        return
    }

    ok = false
}

bar(.x: Int32) -> (.ok: Bool) := {
    ok = true
}

main() -> (.status_code: Int32) := {
    if foo(.x = 42) {
        status_code = 0
        return
    }

    status_code = 1
}
