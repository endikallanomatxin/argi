main(.system: System) -> (.status_code: Int32 = 0) := {
    assume proc_man ::= system.proc_man
    match spawn(.executable = "") {
        ..error error {
            if is(.value = error.reason, .variant = ..invalid_process_argument) {
            } else {
                abort
            }
        }
        ..ok ~child {
            deinit(.self = $&child)
            abort
        }
    }
    match spawn(.executable = "argi-nonexistent-executable-87a6d") {
        ..error error {
            if is(.value = error.reason, .variant = ..process_spawn_failed) {} else { abort }
        }
        ..ok ~child {
            deinit(.self = $&child)
            abort
        }
    }
    executable ::= unwrap_or_abort(.value = get(.self = system.args, .index = 0)).result
    bytes: [3]UInt8 = (97, 0, 98)
    invalid: StringView = "a\0b"
    args: [1]StringView = (invalid)
    match spawn(.executable = executable, .arguments = view(.self = &args)) {
        ..error error {
            if is(.value = error.reason, .variant = ..invalid_process_argument) {
            } else {
                abort
            }
        }
        ..ok ~child {
            deinit(.self = $&child)
            abort
        }
    }
    malformed: [1]UInt8 = (255)
    match string_from_bytes(.bytes = view(&malformed), .allocator = system.page_allocator) {
        ..error error { if error.reason != ..invalid_utf8 { abort } }
        ..ok ~text { abort }
    }
}
