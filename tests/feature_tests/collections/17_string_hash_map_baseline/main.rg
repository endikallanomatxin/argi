main(.system: System = System()) -> (.status_code: Int32) := {
    map ::= StringHashMap#(.value: Int32)(.capacity = 1)

    put#(.value: Int32)(.self = $$&map, .key = "alpha", .value = 1)
    put#(.value: Int32)(.self = $$&map, .key = "beta", .value = 2)
    put#(.value: Int32)(.self = $$&map, .key = "alpha", .value = 7)

    if has#(.value: Int32)(.self = &map, .key = "alpha").ok {
    } else {
        status_code = 1
        return
    }

    if has#(.value: Int32)(.self = &map, .key = "beta").ok {
    } else {
        status_code = 2
        return
    }

    if has#(.value: Int32)(.self = &map, .key = "missing").ok {
        status_code = 3
        return
    }

    alpha ::= get#(.value: Int32)(.self = &map, .key = "alpha").value
    match alpha {
        ..some payload {
            if payload.value != 7 {
                status_code = 4
                return
            }
        }
        ..none {
            status_code = 5
            return
        }
    }

    beta ::= get#(.value: Int32)(.self = &map, .key = "beta").value
    match beta {
        ..some payload {
            if payload.value != 2 {
                status_code = 6
                return
            }
        }
        ..none {
            status_code = 7
            return
        }
    }

    missing ::= get#(.value: Int32)(.self = &map, .key = "missing").value
    if missing? {
        status_code = 8
        return
    }

    removed_beta ::= delete#(.value: Int32)(.self = $$&map, .key = "beta").value
    match removed_beta {
        ..some payload {
            if payload.value != 2 {
                status_code = 9
                return
            }
        }
        ..none {
            status_code = 10
            return
        }
    }

    if has#(.value: Int32)(.self = &map, .key = "beta").ok {
        status_code = 11
        return
    }

    alpha_after_delete ::= get#(.value: Int32)(.self = &map, .key = "alpha").value
    match alpha_after_delete {
        ..some payload {
            if payload.value != 7 {
                status_code = 12
                return
            }
        }
        ..none {
            status_code = 13
            return
        }
    }

    put#(.value: Int32)(.self = $$&map, .key = "gamma", .value = 9)
    removed_gamma ::= delete#(.value: Int32)(.self = $$&map, .key = "gamma").value
    match removed_gamma {
        ..some payload {
            if payload.value != 9 {
                status_code = 14
                return
            }
        }
        ..none {
            status_code = 15
            return
        }
    }

    removed_missing ::= delete#(.value: Int32)(.self = $$&map, .key = "missing").value
    if removed_missing? {
        status_code = 16
        return
    }

    deinit#(.value: Int32)(.self = $$&map)
    status_code = 0
}
