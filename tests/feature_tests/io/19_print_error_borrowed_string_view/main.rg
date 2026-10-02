main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&system.terminal&.stderr

    literal ::= from_literal(.data = "borrowed err")
    text ::= as_view(.self = literal)
    print_error(.value = text)
}
