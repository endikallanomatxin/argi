check_exit(.status: ProcessExitStatus, .expected: UInt32) -> () := {
    match status {
        ..exited payload { if payload.code != expected { abort } }
        ..signaled _ { abort }
    }
}
check_bytes(.reader: $&Reader, .expected: StringView) -> () := {
    i :: UIntNative = 0
    while i < expected.length {
        next ::= unwrap_or_abort(.value = read_byte(.self = reader)).result
        match next {
            ..ok byte { if byte != bytes_get(.view = &expected, .index = i).byte { abort } }
            ..end { abort }
        }
        i = i + 1
    }
    match unwrap_or_abort(.value = read_byte(.self = reader)).result {
        ..end {}
        ..ok _ { abort }
    }
}
child_main(.system: System) -> (.status: Int32 = 7) := {
    if length(.self = system.args).count != 7 { abort }
    expected: Array#(.n = 4, .t: StringView) = ("a b", "a\"b", "trail\\", "á;$(no)")
    empty ::= unwrap_or_abort(.value = get(.self = system.args, .index = 2)).result
    if empty.length != 0 { abort }
    i :: UIntNative = 0
    while i < 4 {
        value ::= unwrap_or_abort(.value = get(.self = system.args, .index = i + 3)).result
        if value != expected[i] { abort }
        i = i + 1
    }
    check_bytes(.reader = $&system.terminal&.stdin, .expected = "hello\n")
    unwrap_or_abort(.value = write(.self = $&system.terminal&.stdout, .text = "hello\n"))
    unwrap_or_abort(.value = flush(.self = $&system.terminal&.stdout))
    unwrap_or_abort(.value = write(.self = $&system.terminal&.stderr, .text = "problem"))
    unwrap_or_abort(.value = flush(.self = $&system.terminal&.stderr))
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    if length(.self = system.args).count == 2 {
        status_code = 23
        return
    }
    if length(.self = system.args).count > 1 {
        status_code = child_main(.system = system).status
        return
    }
    assume proc_man ::= system.proc_man
    executable ::= unwrap_or_abort(.value = get(.self = system.args, .index = 0)).result
    args: Array#(.n = 6, .t: StringView) = ("echo", "", "a b", "a\"b", "trail\\", "á;$(no)")
    child ::= unwrap_or_abort(.value = spawn(.executable = executable,
            .arguments = view(.array = &args), .stdin = ..pipe, .stdout = ..pipe, .stderr = ..pipe)).result
    unwrap_or_abort(.value = write(.self = $&child.stdin, .text = "hello\n"))
    unwrap_or_abort(.value = flush(.self = $&child.stdin))
    unwrap_or_abort(.value = close(.self = $&child.stdin))
    unwrap_or_abort(.value = close(.self = $&child.stdin))
    check_bytes(.reader = $&child.stdout, .expected = "hello\n")
    check_bytes(.reader = $&child.stderr, .expected = "problem")
    check_exit(.status = unwrap_or_abort(.value = wait(.self = $&child)).result, .expected = 7)
    check_exit(.status = unwrap_or_abort(.value = wait(.self = $&child)).result, .expected = 7)
    unwrap_or_abort(.value = terminate(.self = $&child))
    deinit(.self = $&child)
    quick: [1]StringView = ("quick")
    inherited ::= unwrap_or_abort(.value = spawn(.executable = executable,
            .arguments = view(.array = &quick), .stdin = ..discard)).result
    if is_open(.self = &inherited.stdin).ok or is_open(.self = &inherited.stdout).ok { abort }
    match read_byte(.self = $&inherited.stdout) { ..error _ {} ..ok _ { abort } }
    check_exit(.status = unwrap_or_abort(.value = wait(.self = $&inherited)).result, .expected = 23)

}
