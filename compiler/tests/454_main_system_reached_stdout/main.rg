emit_ok(
    .stdout: $&OutputStream#(.text: String) = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> (.ok: Int32) := {
    _ ::= stdout
    ok = 0
}

main(.system: System = System()) -> (.status_code: Int32) := {
    status_code = emit_ok()
}
