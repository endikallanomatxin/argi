python := import ("python")

main := (.system: System) -> (.status_code: Int32 = 0) {

    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    value ::= unwrap_or_abort(.value = python.none(.self = &interpreter)).result
    Deinit#(python.Python).deinit(.self = $&interpreter)
    python.is_none(.self = &value)
}
