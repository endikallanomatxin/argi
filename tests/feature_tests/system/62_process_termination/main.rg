main(.system: System) -> (.status_code: Int32 = 0) := {
    if length(.self = system.args).count > 1 {
        unwrap_or_abort(.value = close(.self = $&system.terminal&.stdin))
        unwrap_or_abort(.value = write(.self = $&system.terminal&.stdout, .text = "R"))
        unwrap_or_abort(.value = flush(.self = $&system.terminal&.stdout))
        assume clock ::= system.clock
        while true {
            unwrap_or_abort(.value = sleep(.duration = unwrap_or_abort(.value = Duration(.seconds = 1)).result))
        }
        return
    }
    assume proc_man ::= system.proc_man
    executable ::= unwrap_or_abort(.value = get(.self = system.args, .index = 0)).result
    args: [1]StringView = ("wait")
    child ::= unwrap_or_abort(.value = spawn(.executable = executable,
            .arguments = view(.array = &args), .stdin = ..pipe, .stdout = ..pipe,
            .stderr    = ..discard)).result
    match unwrap_or_abort(.value = read_byte(.self = $&child.stdout)).result {
        ..ok byte { if byte != 82 { abort } }
        ..end { abort }
    }
    -- Wrong-direction operations fail before crossing the native boundary.
    match read_byte(.self = $&child.stdin) { ..error _ {} ..ok _ { abort } }
    match write_byte(.self = $&child.stdout, .byte = 1) { ..error _ {} ..ok _ { abort } }
    unwrap_or_abort(.value = terminate(.self = $&child))
    status ::= unwrap_or_abort(.value = wait(.self = $&child)).result
    #if target_os("windows") {
        match status { ..exited value { if value.code != 1 { abort } } ..signaled _ { abort } }
    }
    #if target_os("linux") or target_os("macos") {
        match status { ..signaled value { if value.signal != 9 { abort } } ..exited _ { abort } }
    }
    -- Even after the child has exited, a broken pipe is a Writer error.
    match write_byte(.self = $&child.stdin, .byte = 1) { ..error _ {} ..ok _ { abort } }
    deinit(.self = $&child)
    orphan ::= unwrap_or_abort(.value = spawn(.executable = executable,
            .arguments = view(.array = &args), .stdout = ..pipe, .stdin = ..discard,
            .stderr    = ..discard)).result
    match unwrap_or_abort(.value = read_byte(.self = $&orphan.stdout)).result {
        ..ok byte { if byte != 82 { abort } }
        ..end { abort }
    }
    -- Automatic destruction must stop and reap this still-running child.
}
