main := (.system: System) -> (.status_code: Int32 = 0) {
    if length(.self = system.args).count > 1 {
        unwrap_or_abort(.value = close(.self = $&system.terminal&.stdin))
        unwrap_or_abort(.value = write(.self = $&system.terminal&.stdout, .value = "R"))
        unwrap_or_abort(.value = Writer#().flush(.self = $&system.terminal&.stdout))
        assume clock ::= system.clock
        while true {
            unwrap_or_abort(
                .value = sleep(
                    .self     = clock
                    .duration = unwrap_or_abort(
                        .value = duration_from_seconds(.seconds = 1)
                    ).result
                )
            )
        }
        return
    }
    assume proc_man ::= system.proc_man
    executable ::= unwrap_or_abort(.value = get(.self = system.args, .index = 0)).result
    args: [1]StringView = ("wait")
    child ::= unwrap_or_abort(
        .value = spawn(
            .self       = proc_man
            .executable = executable
            .arguments  = view(.self = &args)
            .stdin      = ..pipe
            .stdout     = ..pipe
            .stderr     = ..discard
        )
    ).result
    match unwrap_or_abort(.value = Reader#().read_byte(.self = $&child.stdout)).result {
        ..ok byte { if byte != 82 { abort } }
        ..end { abort }
    }
    -- Wrong-direction operations fail before crossing the native boundary.
    match Reader#().read_byte(.self = $&child.stdin) { ..error _ {} ..ok _ { abort } }
    match Writer#().write_byte(.self = $&child.stdout, .byte = 1) {
        ..error _ {} ..ok _ { abort }
    }
    unwrap_or_abort(.value = terminate(.self = $&child))
    status ::= unwrap_or_abort(.value = wait(.self = $&child)).result
    #if target_os("windows") {
        match status { ..exited value { if value.code != 1 { abort } } ..signaled _ { abort } }
    }
    #if target_os("linux") or target_os("macos") {
        match status {
            ..signaled value { if value.signal != 9 { abort } } ..exited _ { abort }
        }
    }
    -- Even after the child has exited, a broken pipe is a Writer error.
    match Writer#().write_byte(.self = $&child.stdin, .byte = 1) {
        ..error _ {} ..ok _ { abort }
    }
    deinit(.self = $&child)
    orphan ::= unwrap_or_abort(
        .value = spawn(
            .self       = proc_man
            .executable = executable
            .arguments  = view(.self = &args)
            .stdout     = ..pipe
            .stdin      = ..discard
            .stderr     = ..discard
        )
    ).result
    match unwrap_or_abort(.value = Reader#().read_byte(.self = $&orphan.stdout)).result {
        ..ok byte { if byte != 82 { abort } }
        ..end { abort }
    }
    -- Automatic destruction must stop and reap this still-running child.
}
