increment_and_is_true(.value: $&Int32) -> (.ok: Bool) := {
    value& = value& + 1
    ok = true
}

main() -> (.status_code: Int32) := {
    a := true
    b := false
    side_effect :: Int32 = 0

    if a and b {
        status_code = 1
        return
    }

    if a or b {
    } else {
        status_code = 2
        return
    }

    if a or increment_and_is_true(.value = $&side_effect) {
    } else {
        status_code = 3
        return
    }

    if side_effect != 0 {
        status_code = 4
        return
    }

    if b and increment_and_is_true(.value = $&side_effect) {
        status_code = 5
        return
    }

    if side_effect != 0 {
        status_code = 6
        return
    }

    if b or increment_and_is_true(.value = $&side_effect) {
    } else {
        status_code = 7
        return
    }

    if side_effect != 1 {
        status_code = 8
        return
    }

    if a and true or false {
    } else {
        status_code = 9
        return
    }

    status_code = 0
}
