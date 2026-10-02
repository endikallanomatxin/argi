main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    assume writer ::= $&system.terminal&.stderr

    literal ::= from_literal(.data = "error view")
    text ::= as_view(.self = literal)
    print_error(.value = text)
}
