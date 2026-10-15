main(.system: System) -> (.status_code: Int32 = 0) := {
    if length(.self = system.args).count == 2 {
        value ::= unwrap_or_abort(.value = get(.self = system.args, .index = 1)).result
        if value != "done" { abort }
        return
    }
    executable ::= unwrap_or_abort(.value = get(.self = system.args, .index = 0)).result
    child :: Process
    {
        bytes: [4]UInt8 = (100, 111, 110, 101)
        argument: StringView = (.data = &bytes[0], .length = 4)
        args: [1]StringView = (argument)
        child = unwrap_or_abort(.value = spawn(.self = system.proc_man, .executable = executable,
                .arguments = view(.array = &args))).result
    }
    match unwrap_or_abort(.value = wait(.self = $&child)).result {
        ..exited payload { if payload.code != 0 { abort } }
        ..signaled _ { abort }
    }
}
