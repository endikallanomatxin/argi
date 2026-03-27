emit_ok(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> (.ok: Int32) := {
    _ ::= stdout
    ok = 0
}

main(.system: System = System()) -> (.status_code: Int32) := {
    status_code = emit_ok()
}
