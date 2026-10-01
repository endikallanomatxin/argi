main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&system.terminal&.stdout

    literal ::= from_literal(.data = "borrowed view")
    text ::= as_view(.self = literal)
    print(.value = text)
}
