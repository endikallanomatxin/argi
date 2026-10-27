main := (.system: System) -> () {
    child ::= unwrap_or_abort(
        .value = spawn(.self = system.proc_man, .executable = "test", .stdout = ..pipe)
    ).result
    reader ::= $&child.stdout
    deinit(.self = $&child)
    Reader#().read_byte(.self = reader)
}
