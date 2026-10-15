main(.system: System) -> (.status_code: Int32 = 0) := {
    assume proc_man ::= system.proc_man
    match spawn(.executable = "") {
        ..error error {
            if is(.value = error.reason, .variant = ..invalid_process_argument) {} else { abort }
        }
        ..ok ~child { deinit(.self = $&child)
            abort }
    }
    match spawn(.executable = "argi-nonexistent-executable-87a6d") {
        ..error error {
            if is(.value = error.reason, .variant = ..process_spawn_failed) {} else { abort }
        }
        ..ok ~child { deinit(.self = $&child)
            abort }
    }
    executable ::= unwrap_or_abort(.value = get(.self = system.args, .index = 0)).result
    bytes: [3]UInt8 = (97, 0, 98)
    invalid: StringView = (.data = &bytes[0], .length = 3)
    args: [1]StringView = (invalid)
    match spawn(.executable = executable, .arguments = view(.array = &args)) {
        ..error error {
            if is(.value = error.reason, .variant = ..invalid_process_argument) {} else { abort }
        }
        ..ok ~child { deinit(.self = $&child)
            abort }
    }
    malformed: [1]UInt8 = (255)
    invalid_utf8: StringView = (.data = &malformed[0], .length = 1)
    invalid_args: [1]StringView = (invalid_utf8)
    match spawn(.executable = executable, .arguments = view(.array = &invalid_args)) {
        ..error error {
            if is(.value = error.reason, .variant = ..invalid_process_argument) {} else { abort }
        }
        ..ok ~child {
            deinit(.self = $&child)
            abort
        }
    }

}
