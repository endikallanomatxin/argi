main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    map ::= unwrap_or_abort(.value = HashMap#(.key: StringView, .value: Int32)(.capacity = 1))

    unwrap_or_abort(.value = put(.self = $&map, .key = "alpha", .value = 1))
    unwrap_or_abort(.value = put(.self = $&map, .key = "beta", .value = 2))
    unwrap_or_abort(.value = put(.self = $&map, .key = "alpha", .value = 7))

    if contains(.self = &map, .key = "alpha").ok {
    } else {
        status_code = 1
        return
    }

    if contains(.self = &map, .key = "beta").ok {
    } else {
        status_code = 2
        return
    }

    if contains(.self = &map, .key = "missing").ok {
        status_code = 3
        return
    }

    alpha ::= get(.self = &map, .key = "alpha").result
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

    beta ::= get(.self = &map, .key = "beta").result
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

    missing ::= get(.self = &map, .key = "missing").result
    if missing ?{
        status_code = 8
        return
    }

    removed_beta ::= extract(.self = $&map, .key = "beta").result
    match removed_beta {
        ..some payload {
            if payload.value.value != 2 {
                status_code = 9
                return
            }
        }
        ..none {
            status_code = 10
            return
        }
    }

    if contains(.self = &map, .key = "beta").ok {
        status_code = 11
        return
    }

    alpha_after_delete ::= get(.self = &map, .key = "alpha").result
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

    unwrap_or_abort(.value = put(.self = $&map, .key = "gamma", .value = 9))
    removed_gamma ::= extract(.self = $&map, .key = "gamma").result
    match removed_gamma {
        ..some payload {
            if payload.value.value != 9 {
                status_code = 14
                return
            }
        }
        ..none {
            status_code = 15
            return
        }
    }

    removed_missing ::= extract(.self = $&map, .key = "missing").result
    if removed_missing ?{
        status_code = 16
        return
    }

    deinit(.self = $&map)
    status_code = 0
}
